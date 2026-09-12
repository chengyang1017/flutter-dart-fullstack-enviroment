import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
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
  static const rootPath = appRootPath;

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final appRoot = _appRoot();
    final backendRoot = _backendRoot(appRoot);
    final palette = WorkbenchPalette.of(context);

    return Material(
      key: const ValueKey('concept-lib-explorer'),
      color: palette.surface,
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
          Divider(
            height: 1,
            thickness: 1,
            color: palette.border,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 2),
              children: [
                _buildConceptRoot(
                  context,
                  path: appRoot,
                  stableKey: 'app',
                  label: context.l10n.tr('应用', 'App'),
                  icon: Icons.flutter_dash_rounded,
                ),
                if (backendRoot != null)
                  _buildConceptRoot(
                    context,
                    path: backendRoot,
                    stableKey: 'backend',
                    label: context.l10n.tr('后端', 'Backend'),
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
    final palette = WorkbenchPalette.of(context);

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
      textColor: palette.text,
      collapsedTextColor: palette.text,
      iconColor: palette.muted,
      collapsedIconColor: palette.muted,
      leading: Icon(
        icon,
        size: 18,
        color: const Color(0xffd7aa5c),
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
    final palette = WorkbenchPalette.of(context);
    final selected = Theme.of(context).colorScheme.primaryContainer;
    final hover = Theme.of(context).colorScheme.surfaceContainerHigh;

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
        textColor: palette.text,
        collapsedTextColor: palette.text,
        iconColor: palette.muted,
        collapsedIconColor: palette.muted,
        leading: const Icon(
          Icons.folder_outlined,
          size: 18,
          color: Color(0xffd7aa5c),
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
      selectedTileColor: selected,
      hoverColor: hover,
      textColor: palette.text,
      selectedColor: palette.text,
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
      title: type == WorkspaceEntryType.file
          ? context.l10n.tr('新建 Dart 文件', 'New Dart file')
          : context.l10n.tr('新建文件夹', 'New folder'),
      hint: type == WorkspaceEntryType.file
          ? context.l10n.tr('例如 home_screen.dart', 'For example, home_screen.dart')
          : context.l10n.tr('例如 screens', 'For example, screens'),
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
      title: context.l10n.tr('重命名', 'Rename'),
      hint: entry.name,
      initialValue: entry.name,
    );
    if (name == null || name == entry.name) return;

    _runAction(context, () => workspace.renameEntry(entry.path, name));
  }

  Future<void> _delete(BuildContext context, WorkspaceEntry entry) async {
    if (!_insideConceptSource(entry.path)) return;

    final area = _areaLabel(context, entry.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dialogContext.l10n.tr(
            '删除 ${entry.name}？',
            'Delete ${entry.name}?',
          ),
        ),
        content: Text(
          entry.isDirectory
              ? dialogContext.l10n.tr(
                  '这个文件夹以及里面的文件都会从 $area 删除。',
                  'This folder and all files inside it will be removed from $area.',
                )
              : dialogContext.l10n.tr(
                  '这个文件会从 $area 删除。',
                  'This file will be removed from $area.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.tr('删除', 'Delete')),
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

  String _areaLabel(BuildContext context, String path) {
    final appRoot = _appRoot();
    if (path == appRoot || path.startsWith('$appRoot/')) {
      return context.l10n.tr('应用', 'the app');
    }
    return context.l10n.tr('后端', 'the backend');
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
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onChanged: (value) => currentValue = value,
          onFieldSubmitted: (value) {
            Navigator.pop(dialogContext, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, currentValue.trim()),
            child: Text(dialogContext.l10n.tr('确定', 'Confirm')),
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
    final palette = WorkbenchPalette.of(context);

    return Container(
      height: 38,
      color: palette.surfaceRaised,
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          const Icon(
            Icons.folder_special_outlined,
            size: 15,
            color: Color(0xffd7aa5c),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              context.l10n.tr('应用 / 后端', 'APP / BACKEND'),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .7,
                color: palette.text,
              ),
            ),
          ),
          if (dirty)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                Icons.circle,
                size: 7,
                color: palette.accent,
              ),
            ),
          _HeaderAction(
            tooltip: context.l10n.tr(
              '在当前应用 / 后端区域新建文件',
              'Create a file in the current app / backend area',
            ),
            icon: Icons.note_add_outlined,
            onPressed: onCreateFile,
          ),
          _HeaderAction(
            tooltip: context.l10n.tr(
              '在当前应用 / 后端区域新建文件夹',
              'Create a folder in the current app / backend area',
            ),
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
    final palette = WorkbenchPalette.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 29, height: 29),
      splashRadius: 15,
      icon: Icon(
        icon,
        size: 16,
        color: palette.muted,
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
    final palette = WorkbenchPalette.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: palette.text,
            ),
          ),
        ),
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.circle,
              size: 7,
              color: palette.accent,
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
    final palette = WorkbenchPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: context.l10n.tr('更多', 'More'),
      padding: EdgeInsets.zero,
      iconSize: 17,
      icon: Icon(
        Icons.more_vert,
        color: palette.muted,
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
          PopupMenuItem(
            value: 'file',
            child: Text(context.l10n.tr('新建文件', 'New file')),
          ),
        if (onCreateDirectory != null)
          PopupMenuItem(
            value: 'folder',
            child: Text(context.l10n.tr('新建文件夹', 'New folder')),
          ),
        PopupMenuItem(
          value: 'rename',
          child: Text(context.l10n.tr('重命名', 'Rename')),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(context.l10n.tr('删除', 'Delete')),
        ),
      ],
    );
  }
}
