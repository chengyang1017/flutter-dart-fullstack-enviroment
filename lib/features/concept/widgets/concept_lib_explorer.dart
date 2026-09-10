import 'dart:convert';

import 'package:flutter/material.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_entry.dart';
import '../../workspace/widgets/workspace_file_visuals.dart';

class ConceptLibExplorer extends StatelessWidget {
  const ConceptLibExplorer({
    super.key,
    required this.workspace,
    required this.onOpenFile,
  });

  static const appRootPath = 'lib';
  static const backendRootPath = 'backend';
  static const serverpodBackendRootPath = 'serverpod/practice_server/lib';

  /// Kept for callers/tests that still refer to the old concept root constant.
  static const rootPath = appRootPath;

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  static const _background = _ConceptExplorerPalette.background;
  static const _textColor = _ConceptExplorerPalette.text;
  static const _mutedColor = _ConceptExplorerPalette.muted;

  @override
  Widget build(BuildContext context) {
    final appRoot = _appRoot();
    final backendRoot = _backendRoot(appRoot);

    return Material(
      key: const ValueKey('concept-lib-explorer'),
      color: _background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            dirty: workspace.isDirty,
            onCreateFile: () => _createEntry(
              context,
              directory: _activeDirectory(),
              type: WorkspaceEntryType.file,
            ),
            onCreateDirectory: () => _createEntry(
              context,
              directory: _activeDirectory(),
              type: WorkspaceEntryType.directory,
            ),
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: _ConceptExplorerPalette.border,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 2),
              children: [
                _buildConceptRoot(
                  context,
                  path: appRoot,
                  stableKey: 'app',
                  label: '应用',
                  icon: Icons.flutter_dash_rounded,
                ),
                if (backendRoot != null)
                  _buildConceptRoot(
                    context,
                    path: backendRoot,
                    stableKey: 'backend',
                    label: '后端',
                    icon: Icons.dns_outlined,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _appRoot() {
    if (_hasDirectory(appRootPath)) return appRootPath;

    final candidates = <String>[];
    for (final entry in workspace.entries) {
      if (!entry.isFile || !entry.isText) continue;
      if (entry.path != 'pubspec.yaml' &&
          !entry.path.endsWith('/pubspec.yaml')) {
        continue;
      }
      if (!_looksLikeFlutterPubspec(entry.content)) continue;

      final projectRoot = _manifestRoot(entry.path, 'pubspec.yaml');
      final sourceRoot = _join(projectRoot, 'lib');
      final main = workspace.entryAt(_join(sourceRoot, 'main.dart'));
      if (main == null || !main.isFile) continue;
      candidates.add(sourceRoot);
    }

    if (candidates.isEmpty) return appRootPath;
    candidates.sort(_compareSourceRoots);
    return candidates.first;
  }

  String? _backendRoot(String appRoot) {
    for (final path in const <String>[
      backendRootPath,
      serverpodBackendRootPath,
    ]) {
      if (_hasDirectory(path)) return path;
    }

    final appProjectRoot = _parentPath(appRoot);
    final serverpodCandidates = <String>[];
    final nodeCandidates = <String>[];

    for (final entry in workspace.entries) {
      if (!entry.isFile || !entry.isText) continue;

      if (entry.path == 'pubspec.yaml' ||
          entry.path.endsWith('/pubspec.yaml')) {
        final root = _manifestRoot(entry.path, 'pubspec.yaml');
        if (root == appProjectRoot ||
            !_looksLikeServerpodPubspec(entry.content)) {
          continue;
        }

        final sourceRoot = _join(root, 'lib');
        if (_hasDirectory(sourceRoot)) {
          serverpodCandidates.add(sourceRoot);
        }
        continue;
      }

      if (entry.path == 'package.json' ||
          entry.path.endsWith('/package.json')) {
        final root = _manifestRoot(entry.path, 'package.json');
        if (root == appProjectRoot || !_looksLikeNodeBackend(entry.content)) {
          continue;
        }

        final sourceRoot = _join(root, 'src');
        nodeCandidates.add(_hasDirectory(sourceRoot) ? sourceRoot : root);
      }
    }

    serverpodCandidates.sort(_compareSourceRoots);
    if (serverpodCandidates.isNotEmpty) return serverpodCandidates.first;

    nodeCandidates.sort(_compareSourceRoots);
    if (nodeCandidates.isNotEmpty) return nodeCandidates.first;
    return null;
  }

  bool _hasDirectory(String path) {
    if (path.isEmpty) return false;
    return workspace.entryAt(path)?.isDirectory == true ||
        workspace.childrenOf(path).isNotEmpty;
  }

  bool _looksLikeFlutterPubspec(String content) {
    return RegExp(r'^\s*flutter\s*:\s*$', multiLine: true).hasMatch(content) ||
        RegExp(r'^\s*sdk\s*:\s*flutter\s*$', multiLine: true).hasMatch(content);
  }

  bool _looksLikeServerpodPubspec(String content) {
    return RegExp(r'^\s*serverpod\s*:', multiLine: true).hasMatch(content);
  }

  bool _looksLikeNodeBackend(String content) {
    try {
      final root = jsonDecode(content);
      if (root is! Map) return false;
      final packages = <String>{
        ..._dependencyNames(root['dependencies']),
        ..._dependencyNames(root['devDependencies']),
      };
      return const <String>{
        'express',
        '@nestjs/core',
        'fastify',
        'koa',
        'hono',
        '@hapi/hapi',
      }.any(packages.contains);
    } catch (_) {
      return false;
    }
  }

  Set<String> _dependencyNames(Object? value) {
    if (value is! Map) return const <String>{};
    return value.keys.whereType<String>().toSet();
  }

  String _manifestRoot(String path, String fileName) {
    if (path == fileName) return '';
    return path.substring(0, path.length - '/$fileName'.length);
  }

  String _join(String root, String path) => root.isEmpty ? path : '$root/$path';

  String _parentPath(String path) {
    final slash = path.lastIndexOf('/');
    return slash == -1 ? '' : path.substring(0, slash);
  }

  int _compareSourceRoots(String a, String b) {
    final depth = a.split('/').length.compareTo(b.split('/').length);
    return depth != 0 ? depth : a.compareTo(b);
  }

  Widget _buildConceptRoot(
    BuildContext context, {
    required String path,
    required String stableKey,
    required String label,
    required IconData icon,
  }) {
    return ExpansionTile(
      key: ValueKey('concept-root-$stableKey'),
      initiallyExpanded: true,
      onExpansionChanged: (expanded) {
        if (workspace.entryAt(path)?.isDirectory == true) {
          workspace.setDirectoryExpanded(path, expanded);
        }
      },
      tilePadding: const EdgeInsets.only(left: 8, right: 2),
      childrenPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      textColor: _textColor,
      collapsedTextColor: _textColor,
      iconColor: _mutedColor,
      collapsedIconColor: _mutedColor,
      leading: Icon(
        icon,
        size: 18,
        color: _ConceptExplorerPalette.folder,
      ),
      title: _EntryLabel(
        name: label,
        dirty: _hasDirtyDescendant(path),
      ),
      children: workspace
          .childrenOf(path)
          .map((entry) => _buildEntry(context, entry, 0))
          .toList(growable: false),
    );
  }

  String _activeDirectory() {
    final appRoot = _appRoot();
    final parent = workspace.activeEntry?.parentPath ?? appRoot;
    final backendRoot = _backendRoot(appRoot);
    for (final root in <String>[
      appRoot,
      if (backendRoot != null) backendRoot,
    ]) {
      if (parent == root || parent.startsWith('$root/')) {
        return parent;
      }
    }
    return appRoot;
  }

  Widget _buildEntry(
    BuildContext context,
    WorkspaceEntry entry,
    int depth,
  ) {
    if (entry.isDirectory) {
      final expanded = workspace.isDirectoryExpanded(entry.path);
      return ExpansionTile(
        key: ValueKey('concept-lib-entry-${entry.path}'),
        initiallyExpanded: workspace.isDirectoryExpanded(entry.path),
        onExpansionChanged: (expanded) {
          workspace.setDirectoryExpanded(entry.path, expanded);
        },
        tilePadding: EdgeInsets.only(
          left: 8.0 + depth * 12,
          right: 2,
        ),
        childrenPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        textColor: _textColor,
        collapsedTextColor: _textColor,
        iconColor: _mutedColor,
        collapsedIconColor: _mutedColor,
        leading: const Icon(
          Icons.folder_outlined,
          size: 18,
          color: _ConceptExplorerPalette.folder,
        ),
        title: _EntryLabel(
          name: entry.name,
          dirty: _hasDirtyDescendant(entry.path),
        ),
        trailing: _EntryMenu(
          onCreateFile: () => _createEntry(
            context,
            directory: entry.path,
            type: WorkspaceEntryType.file,
          ),
          onCreateDirectory: () => _createEntry(
            context,
            directory: entry.path,
            type: WorkspaceEntryType.directory,
          ),
          onRename: () => _rename(context, entry),
          onDelete: () => _delete(context, entry),
        ),
        children: expanded
            ? workspace
                .childrenOf(entry.path)
                .map((child) => _buildEntry(context, child, depth + 1))
                .toList(growable: false)
            : const <Widget>[],
      );
    }

    return ListTile(
      key: ValueKey('concept-lib-entry-${entry.path}'),
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.only(
        left: 28.0 + depth * 12,
        right: 2,
      ),
      selected: !entry.isBinary && workspace.activePath == entry.path,
      selectedTileColor: _ConceptExplorerPalette.selected,
      hoverColor: _ConceptExplorerPalette.hover,
      textColor: _textColor,
      selectedColor: _textColor,
      leading: Builder(
        builder: (context) {
          final visual = WorkspaceFileVisual.forName(
            entry.name,
            binary: entry.isBinary,
          );
          return Icon(visual.icon, size: 17, color: visual.color);
        },
      ),
      title: _EntryLabel(
        name: entry.name,
        dirty: workspace.isFileDirty(entry.path),
      ),
      onTap: entry.isBinary ? null : () => onOpenFile(entry.path),
      trailing: _EntryMenu(
        onRename: () => _rename(context, entry),
        onDelete: () => _delete(context, entry),
      ),
    );
  }

  bool _hasDirtyDescendant(String directory) {
    return workspace.hasDirtyFileDescendant(directory);
  }

  Future<void> _createEntry(
    BuildContext context, {
    required String directory,
    required WorkspaceEntryType type,
  }) async {
    final safeDirectory =
        _insideConceptSource(directory) ? directory : _appRoot();
    final name = await _askForName(
      context,
      title: type == WorkspaceEntryType.file ? '新建 Dart 文件' : '新建文件夹',
      hint: type == WorkspaceEntryType.file
          ? '例如 home_screen.dart'
          : '例如 screens',
    );
    if (name == null) return;

    _runAction(context, () {
      if (type == WorkspaceEntryType.file) {
        final path = workspace.createFile(safeDirectory, name);
        onOpenFile(path);
      } else {
        workspace.createDirectory(safeDirectory, name);
      }
    });
  }

  Future<void> _rename(BuildContext context, WorkspaceEntry entry) async {
    if (!_insideConceptSource(entry.path)) return;

    final name = await _askForName(
      context,
      title: '重命名',
      hint: entry.name,
      initialValue: entry.name,
    );
    if (name == null || name == entry.name) return;

    _runAction(context, () => workspace.renameEntry(entry.path, name));
  }

  Future<void> _delete(BuildContext context, WorkspaceEntry entry) async {
    if (!_insideConceptSource(entry.path)) return;

    final area = _areaLabel(entry.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${entry.name}？'),
        content: Text(
          entry.isDirectory ? '这个文件夹以及里面的文件都会从 $area 删除。' : '这个文件会从 $area 删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      _runAction(context, () => workspace.deleteEntry(entry.path));
    }
  }

  bool _insideConceptSource(String path) {
    final appRoot = _appRoot();
    if (path == appRoot || path.startsWith('$appRoot/')) return true;
    final backendRoot = _backendRoot(appRoot);
    return backendRoot != null &&
        (path == backendRoot || path.startsWith('$backendRoot/'));
  }

  String _areaLabel(String path) {
    final appRoot = _appRoot();
    if (path == appRoot || path.startsWith('$appRoot/')) return '应用';
    return '后端';
  }

  Future<String?> _askForName(
    BuildContext context, {
    required String title,
    required String hint,
    String? initialValue,
  }) async {
    var currentValue = initialValue ?? '';

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onChanged: (value) => currentValue = value,
          onFieldSubmitted: (value) {
            Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, currentValue.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (value == null || value.isEmpty) return null;
    return value;
  }

  void _runAction(BuildContext context, VoidCallback action) {
    try {
      action();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.dirty,
    required this.onCreateFile,
    required this.onCreateDirectory,
  });

  final bool dirty;
  final VoidCallback onCreateFile;
  final VoidCallback onCreateDirectory;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: _ConceptExplorerPalette.section,
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          const Icon(
            Icons.folder_special_outlined,
            size: 15,
            color: _ConceptExplorerPalette.folder,
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              '应用 / 后端',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: _ConceptExplorerPalette.text,
              ),
            ),
          ),
          if (dirty)
            const Padding(
              padding: EdgeInsets.only(right: 5),
              child: Icon(
                Icons.circle,
                size: 7,
                color: _ConceptExplorerPalette.accent,
              ),
            ),
          _HeaderAction(
            tooltip: '在当前应用 / 后端区域新建文件',
            icon: Icons.note_add_outlined,
            onPressed: onCreateFile,
          ),
          _HeaderAction(
            tooltip: '在当前应用 / 后端区域新建文件夹',
            icon: Icons.create_new_folder_outlined,
            onPressed: onCreateDirectory,
          ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 29, height: 29),
      splashRadius: 15,
      icon: Icon(
        icon,
        size: 16,
        color: _ConceptExplorerPalette.muted,
      ),
    );
  }
}

class _EntryLabel extends StatelessWidget {
  const _EntryLabel({
    required this.name,
    required this.dirty,
  });

  final String name;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: _ConceptExplorerPalette.text,
            ),
          ),
        ),
        if (dirty)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(
              Icons.circle,
              size: 7,
              color: _ConceptExplorerPalette.accent,
            ),
          ),
      ],
    );
  }
}

class _EntryMenu extends StatelessWidget {
  const _EntryMenu({
    required this.onRename,
    required this.onDelete,
    this.onCreateFile,
    this.onCreateDirectory,
  });

  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onCreateFile;
  final VoidCallback? onCreateDirectory;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      padding: EdgeInsets.zero,
      iconSize: 17,
      icon: const Icon(
        Icons.more_vert,
        color: _ConceptExplorerPalette.muted,
      ),
      onSelected: (value) {
        switch (value) {
          case 'file':
            onCreateFile?.call();
            break;
          case 'folder':
            onCreateDirectory?.call();
            break;
          case 'rename':
            onRename();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        if (onCreateFile != null)
          const PopupMenuItem(value: 'file', child: Text('新建文件')),
        if (onCreateDirectory != null)
          const PopupMenuItem(value: 'folder', child: Text('新建文件夹')),
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
  }
}

abstract final class _ConceptExplorerPalette {
  static const background = Color(0xff111318);
  static const section = Color(0xff15191f);
  static const border = Color(0xff272d36);
  static const text = Color(0xffd7dce5);
  static const muted = Color(0xff8b93a1);
  static const accent = Color(0xff82aaff);
  static const selected = Color(0xff202733);
  static const hover = Color(0xff191e26);
  static const folder = Color(0xffd7aa5c);
}
