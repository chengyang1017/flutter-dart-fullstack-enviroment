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

  static const rootPath = 'lib';

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  static const _background = _ConceptExplorerPalette.background;
  static const _textColor = _ConceptExplorerPalette.text;
  static const _mutedColor = _ConceptExplorerPalette.muted;

  @override
  Widget build(BuildContext context) {
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
              children: workspace
                  .childrenOf(rootPath)
                  .map((entry) => _buildEntry(context, entry, 0))
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }

  String _activeDirectory() {
    final parent = workspace.activeEntry?.parentPath ?? rootPath;
    if (parent == rootPath || parent.startsWith('$rootPath/')) {
      return parent;
    }
    return rootPath;
  }

  Widget _buildEntry(
    BuildContext context,
    WorkspaceEntry entry,
    int depth,
  ) {
    if (entry.isDirectory) {
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
        children: workspace
            .childrenOf(entry.path)
            .map((child) => _buildEntry(context, child, depth + 1))
            .toList(growable: false),
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
    return workspace.entries.any(
      (entry) =>
          entry.isFile &&
          entry.path.startsWith('$directory/') &&
          workspace.isFileDirty(entry.path),
    );
  }

  Future<void> _createEntry(
    BuildContext context, {
    required String directory,
    required WorkspaceEntryType type,
  }) async {
    final safeDirectory = _insideLib(directory) ? directory : rootPath;
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
    if (!_insideLib(entry.path)) return;

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
    if (!_insideLib(entry.path)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${entry.name}？'),
        content: Text(
          entry.isDirectory
              ? '这个文件夹以及里面的文件都会从 lib/ 删除。'
              : '这个文件会从 lib/ 删除。',
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

  bool _insideLib(String path) =>
      path == rootPath || path.startsWith('$rootPath/');

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
              'LIB FILES',
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
            tooltip: '在 lib/ 新建文件',
            icon: Icons.note_add_outlined,
            onPressed: onCreateFile,
          ),
          _HeaderAction(
            tooltip: '在 lib/ 新建文件夹',
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
