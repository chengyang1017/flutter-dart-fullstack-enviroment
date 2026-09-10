import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/workspace_controller.dart';
import '../models/workspace_entry.dart';
import 'workspace_file_visuals.dart';

abstract final class _WorkspaceExplorerPalette {
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

class WorkspaceFileExplorer extends StatelessWidget {
  const WorkspaceFileExplorer({
    super.key,
    required this.workspace,
    required this.onOpenFile,
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  static const _panelBackground = _WorkspaceExplorerPalette.background;
  static const _entryTextColor = _WorkspaceExplorerPalette.text;
  static const _mutedIconColor = _WorkspaceExplorerPalette.muted;

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
            onMoveToRoot: (sourcePath) {
              unawaited(
                _confirmMove(
                  context,
                  sourcePath: sourcePath,
                  targetDirectory: '',
                ),
              );
            },
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: _WorkspaceExplorerPalette.border,
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final rootEntries = workspace.childrenOf('');
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: rootEntries.length,
                  itemBuilder: (context, index) {
                    return _buildEntry(context, rootEntries[index], 0);
                  },
                );
              },
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
      final expanded = workspace.isDirectoryExpanded(entry.path);
      final folder = DragTarget<String>(
        onWillAccept: (sourcePath) {
          if (sourcePath == null) return false;
          return _canMoveToDirectory(sourcePath, entry.path);
        },
        onAccept: (sourcePath) {
          unawaited(
            _confirmMove(
              context,
              sourcePath: sourcePath,
              targetDirectory: entry.path,
            ),
          );
        },
        builder: (context, candidates, rejected) {
          final highlighted = candidates.isNotEmpty;
          return Container(
            color: highlighted ? _WorkspaceExplorerPalette.selected : null,
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
                color: _WorkspaceExplorerPalette.folder,
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
              children: expanded
                  ? workspace
                      .childrenOf(entry.path)
                      .map((child) => _buildEntry(context, child, depth + 1))
                      .toList(growable: false)
                  : const <Widget>[],
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
      selectedTileColor: _WorkspaceExplorerPalette.selected,
      hoverColor: _WorkspaceExplorerPalette.hover,
      iconColor: _mutedIconColor,
      selectedColor: _entryTextColor,
      textColor: _entryTextColor,
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
    final fileVisual = entry.isDirectory
        ? null
        : WorkspaceFileVisual.forName(
            entry.name,
            binary: entry.isBinary,
          );

    Widget buildFeedback() {
      return Material(
        elevation: 6,
        color: _WorkspaceExplorerPalette.selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                entry.isDirectory ? Icons.folder_outlined : fileVisual!.icon,
                size: 16,
                color: entry.isDirectory
                    ? _WorkspaceExplorerPalette.folder
                    : fileVisual!.color,
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
      );
    }

    final childWhenDragging = Opacity(
      opacity: .35,
      child: child,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      return LongPressDraggable<String>(
        data: entry.path,
        delay: const Duration(milliseconds: 450),
        hapticFeedbackOnStart: true,
        feedback: buildFeedback(),
        childWhenDragging: childWhenDragging,
        child: child,
      );
    }

    return Draggable<String>(
      data: entry.path,
      feedback: buildFeedback(),
      childWhenDragging: childWhenDragging,
      child: child,
    );
  }

  bool _canMoveToDirectory(String sourcePath, String targetDirectory) {
    final source = workspace.entryAt(sourcePath);
    if (source == null) return false;

    if (source.path == targetDirectory ||
        source.parentPath == targetDirectory) {
      return false;
    }

    if (targetDirectory.isNotEmpty) {
      final target = workspace.entryAt(targetDirectory);
      if (target == null || !target.isDirectory) return false;
    }

    if (source.isDirectory && targetDirectory.startsWith('${source.path}/')) {
      return false;
    }

    return true;
  }

  Future<void> _confirmMove(
    BuildContext context, {
    required String sourcePath,
    required String targetDirectory,
  }) async {
    if (!_canMoveToDirectory(sourcePath, targetDirectory)) return;

    final entry = workspace.entryAt(sourcePath);
    if (entry == null) return;

    final targetPath =
        targetDirectory.isEmpty ? entry.name : '$targetDirectory/${entry.name}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(entry.isDirectory ? '移动文件夹？' : '移动文件？'),
        content: Text(
          '$sourcePath\n'
          '→ $targetPath\n\n'
          '确认移动到这个位置吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移动'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Re-check after the dialog in case the tree changed while it was open.
    if (!_canMoveToDirectory(sourcePath, targetDirectory)) return;
    final currentEntry = workspace.entryAt(sourcePath);
    if (currentEntry == null) return;

    final currentTargetPath = targetDirectory.isEmpty
        ? currentEntry.name
        : '$targetDirectory/${currentEntry.name}';

    try {
      workspace.moveEntry(sourcePath, targetDirectory);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final destinationLabel =
        targetDirectory.isEmpty ? '项目根目录' : targetDirectory;

    messenger.showSnackBar(
      SnackBar(
        content: Text('已移动 ${currentEntry.name} 到 $destinationLabel'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            try {
              workspace.relocateEntry(currentTargetPath, sourcePath);
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(content: Text('撤销失败：$error')),
              );
            }
          },
        ),
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
        final highlighted = candidates.isNotEmpty;

        return Container(
          height: 38,
          color: highlighted
              ? _WorkspaceExplorerPalette.selected
              : _WorkspaceExplorerPalette.section,
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 15,
                color: _WorkspaceExplorerPalette.folder,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'PROJECT FILES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                    color: _WorkspaceExplorerPalette.text,
                  ),
                ),
              ),
              if (workspace.isDirty)
                Tooltip(
                  message: '${workspace.changes.length} 个 Workspace 修改',
                  child: const Padding(
                    padding: EdgeInsets.only(right: 5),
                    child: Icon(
                      Icons.circle,
                      size: 7,
                      color: _WorkspaceExplorerPalette.accent,
                    ),
                  ),
                ),
              _HeaderAction(
                tooltip: '新建文件',
                icon: Icons.note_add_outlined,
                onPressed: onCreateFile,
              ),
              _HeaderAction(
                tooltip: '新建文件夹',
                icon: Icons.create_new_folder_outlined,
                onPressed: onCreateDirectory,
              ),
            ],
          ),
        );
      },
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
        color: _WorkspaceExplorerPalette.muted,
      ),
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
              color: _WorkspaceExplorerPalette.text,
            ),
          ),
        ),
        if (dirty)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(
              Icons.circle,
              size: 7,
              color: _WorkspaceExplorerPalette.accent,
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
        color: _WorkspaceExplorerPalette.muted,
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
