import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../models/workspace_entry.dart';

class WorkspaceFileExplorer extends StatelessWidget {
  const WorkspaceFileExplorer({
    super.key,
    required this.workspace,
    required this.onOpenFile,
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  static const _panelBackground = Color(0xff15171b);
  static const _entryTextColor = Color(0xffd6deeb);
  static const _mutedIconColor = Color(0xff9da5b4);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExplorerHeader(
            workspace: workspace,
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
            onMoveToRoot: (sourcePath) => _runAction(
              context,
              () => workspace.moveEntry(sourcePath, ''),
            ),
          ),
          const Divider(height: 1, color: Color(0xff2c313c)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: workspace
                  .childrenOf('')
                  .map((entry) => _buildEntry(context, entry, 0))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _activeDirectory() {
    final active = workspace.activeEntry;
    return active?.parentPath ?? '';
  }

  Widget _buildEntry(
    BuildContext context,
    WorkspaceEntry entry,
    int depth,
  ) {
    if (entry.isDirectory) {
      final folder = DragTarget<String>(
        onWillAccept: (sourcePath) {
          if (sourcePath == null || sourcePath == entry.path) return false;
          return !entry.path.startsWith('$sourcePath/');
        },
        onAccept: (sourcePath) => _runAction(
          context,
          () => workspace.moveEntry(sourcePath, entry.path),
        ),
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          return Container(
            color: highlighted ? const Color(0xff202938) : null,
            child: ExpansionTile(
              key: PageStorageKey('workspace-${entry.id}'),
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
              textColor: _entryTextColor,
              collapsedTextColor: _entryTextColor,
              iconColor: _mutedIconColor,
              collapsedIconColor: _mutedIconColor,
              leading: const Icon(
                Icons.folder_outlined,
                size: 18,
                color: Color(0xffdcb67a),
              ),
              title: _EntryLabel(
                entry: entry,
                dirty: _hasDirtyDescendant(entry.path),
              ),
              trailing: _EntryMenu(
                onRename: () => _rename(context, entry),
                onDelete: () => _delete(context, entry),
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
              ),
              children: workspace
                  .childrenOf(entry.path)
                  .map((child) => _buildEntry(context, child, depth + 1))
                  .toList(),
            ),
          );
        },
      );

      return _draggable(entry, folder);
    }

    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.only(
        left: 28.0 + depth * 12,
        right: 2,
      ),
      selected: !entry.isBinary && workspace.activePath == entry.path,
      selectedTileColor: const Color(0xff242832),
      iconColor: _mutedIconColor,
      selectedColor: _entryTextColor,
      textColor: _entryTextColor,
      leading: Icon(
        entry.isBinary ? Icons.image_outlined : _fileIcon(entry.name),
        size: 17,
        color: _mutedIconColor,
      ),
      title: _EntryLabel(
        entry: entry,
        dirty: workspace.isFileDirty(entry.path),
      ),
      subtitle: entry.isBinary
          ? const Text(
              'Binary asset · preserved, not editable',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Color(0xff7f8898)),
            )
          : null,
      onTap: () => _openFile(context, entry),
      trailing: _EntryMenu(
        onRename: () => _rename(context, entry),
        onDelete: () => _delete(context, entry),
      ),
    );

    return _draggable(entry, tile);
  }

  void _openFile(BuildContext context, WorkspaceEntry entry) {
    if (!entry.isBinary) {
      onOpenFile(entry.path);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${entry.name} 是二进制资源。Workspace 会原样保存、运行和导出，但不会在代码编辑器中把它当文本打开。',
        ),
      ),
    );
  }

  Widget _draggable(WorkspaceEntry entry, Widget child) {
  return Draggable<String>(
    data: entry.path,
    feedback: Material(
      elevation: 6,
      color: const Color(0xff242832),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              entry.isDirectory
                  ? Icons.folder_outlined
                  : entry.isBinary
                      ? Icons.image_outlined
                      : _fileIcon(entry.name),
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              entry.name,
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
    childWhenDragging: Opacity(
      opacity: .35,
      child: child,
    ),
    child: child,
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
    final name = await _askForName(
      context,
      title: type == WorkspaceEntryType.file ? '新建文件' : '新建文件夹',
      hint: type == WorkspaceEntryType.file
          ? '例如 home_screen.dart'
          : '例如 screens',
    );
    if (name == null) return;

    _runAction(context, () {
      if (type == WorkspaceEntryType.file) {
        final path = workspace.createFile(directory, name);
        onOpenFile(path);
      } else {
        workspace.createDirectory(directory, name);
      }
    });
  }

  Future<void> _rename(BuildContext context, WorkspaceEntry entry) async {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${entry.name}？'),
        content: Text(
          entry.isDirectory
              ? '这个文件夹以及里面的文件都会从当前练习 Workspace 删除。'
              : '这个文件会从当前练习 Workspace 删除。',
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
      workspace.deleteEntry(entry.path);
    }
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
        decoration: InputDecoration(
          hintText: hint,
        ),
        onChanged: (value) {
          currentValue = value;
        },
        onFieldSubmitted: (value) {
          Navigator.pop(
            context,
            value.trim(),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              currentValue.trim(),
            );
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );

  if (value == null || value.isEmpty) {
    return null;
  }

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

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.tune;
    if (name.endsWith('.json')) return Icons.data_object;
    return Icons.description_outlined;
  }
}

class _ExplorerHeader extends StatelessWidget {
  const _ExplorerHeader({
    required this.workspace,
    required this.onCreateFile,
    required this.onCreateDirectory,
    required this.onMoveToRoot,
  });

  final WorkspaceController workspace;
  final VoidCallback onCreateFile;
  final VoidCallback onCreateDirectory;
  final ValueChanged<String> onMoveToRoot;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAccept: (path) {
        if (path == null) return false;
        final entry = workspace.entryAt(path);
        return entry != null && entry.parentPath.isNotEmpty;
      },
      onAccept: onMoveToRoot,
      builder: (context, candidates, rejected) {
        return Container(
          height: 40,
          color: candidates.isNotEmpty ? const Color(0xff202938) : null,
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'PROJECT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    color: Color(0xffc5ccda),
                  ),
                ),
              ),
              if (workspace.isDirty)
                Tooltip(
                  message: '${workspace.changes.length} 个 Workspace 修改',
                  child: const Icon(
                    Icons.circle,
                    size: 8,
                    color: Color(0xff82aaff),
                  ),
                ),
              IconButton(
                tooltip: '新建文件',
                visualDensity: VisualDensity.compact,
                onPressed: onCreateFile,
                icon: const Icon(
                  Icons.note_add_outlined,
                  size: 18,
                  color: Color(0xffaab2bf),
                ),
              ),
              IconButton(
                tooltip: '新建文件夹',
                visualDensity: VisualDensity.compact,
                onPressed: onCreateDirectory,
                icon: const Icon(
                  Icons.create_new_folder_outlined,
                  size: 18,
                  color: Color(0xffaab2bf),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EntryLabel extends StatelessWidget {
  const _EntryLabel({required this.entry, required this.dirty});

  final WorkspaceEntry entry;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xffd6deeb),
            ),
          ),
        ),
        if (dirty)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(
              Icons.circle,
              size: 7,
              color: Color(0xff82aaff),
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
        color: Color(0xff8f98a8),
      ),
      onSelected: (value) {
        switch (value) {
          case 'file':
            onCreateFile?.call();
          case 'folder':
            onCreateDirectory?.call();
          case 'rename':
            onRename();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => [
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
