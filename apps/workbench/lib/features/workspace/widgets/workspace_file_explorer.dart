import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../controllers/workspace_controller.dart';
import '../models/workspace_entry.dart';
import 'workspace_file_visuals.dart';

class WorkspaceFileExplorer extends StatelessWidget {
  const WorkspaceFileExplorer({
    super.key,
    required this.workspace,
    required this.onOpenFile,
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onOpenFile;

  static const _folderColor = Color(0xffd7aa5c);

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Material(
      color: palette.background,
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
          Divider(
            height: 1,
            thickness: 1,
            color: palette.border,
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

  String _activeDirectory() => workspace.activeEntry?.parentPath ?? '';

  Widget _buildEntry(
    BuildContext context,
    WorkspaceEntry entry,
    int depth,
  ) {
    final palette = WorkbenchPalette.of(context);
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
            color: highlighted ? palette.selection : null,
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
              textColor: palette.text,
              collapsedTextColor: palette.text,
              iconColor: palette.muted,
              collapsedIconColor: palette.muted,
              leading: const Icon(
                Icons.folder_outlined,
                size: 18,
                color: _folderColor,
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

      return _draggable(context, entry, folder);
    }

    final tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.only(
        left: 28.0 + depth * 12,
        right: 2,
      ),
      selected: !entry.isBinary && workspace.activePath == entry.path,
      selectedTileColor: palette.selection,
      hoverColor: palette.surfaceRaised,
      iconColor: palette.muted,
      selectedColor: palette.text,
      textColor: palette.text,
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
          ? Text(
              context.l10n.tr(
                '二进制资源 · 原样保存，不可编辑',
                'Binary asset · preserved, not editable',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: palette.muted),
            )
          : null,
      onTap: () => _openFile(context, entry),
      trailing: _EntryMenu(
        onRename: () => _rename(context, entry),
        onDelete: () => _delete(context, entry),
      ),
    );

    return _draggable(context, entry, tile);
  }

  void _openFile(BuildContext context, WorkspaceEntry entry) {
    if (!entry.isBinary) {
      onOpenFile(entry.path);
      return;
    }
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.tr(
            '${entry.name} 是二进制资源。Workspace 会原样保存、运行和导出，但不会在代码编辑器中把它当文本打开。',
            '${entry.name} is a binary asset. The Workspace preserves, runs, and exports it unchanged, but it cannot be opened as text in the code editor.',
          ),
        ),
      ),
    );
  }

  Widget _draggable(
    BuildContext context,
    WorkspaceEntry entry,
    Widget child,
  ) {
    final palette = WorkbenchPalette.of(context);
    final fileVisual = entry.isDirectory
        ? null
        : WorkspaceFileVisual.forName(
            entry.name,
            binary: entry.isBinary,
          );

    Widget buildFeedback() {
      return Material(
        elevation: 6,
        color: palette.selection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                entry.isDirectory ? Icons.folder_outlined : fileVisual!.icon,
                size: 16,
                color: entry.isDirectory ? _folderColor : fileVisual!.color,
              ),
              const SizedBox(width: 6),
              Text(entry.name, style: TextStyle(color: palette.text)),
            ],
          ),
        ),
      );
    }

    final childWhenDragging = Opacity(opacity: .35, child: child);
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
    if (source.path == targetDirectory || source.parentPath == targetDirectory) {
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

    final l10n = context.l10n;
    final targetPath =
        targetDirectory.isEmpty ? entry.name : '$targetDirectory/${entry.name}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          entry.isDirectory
              ? l10n.tr('移动文件夹？', 'Move folder?')
              : l10n.tr('移动文件？', 'Move file?'),
        ),
        content: Text(
          '$sourcePath\n→ $targetPath\n\n${l10n.tr('确认移动到这个位置吗？', 'Move it to this location?')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.tr('移动', 'Move')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
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
    final destinationLabel = targetDirectory.isEmpty
        ? l10n.tr('项目根目录', 'project root')
        : targetDirectory;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.tr(
            '已移动 ${currentEntry.name} 到 $destinationLabel',
            'Moved ${currentEntry.name} to $destinationLabel',
          ),
        ),
        action: SnackBarAction(
          label: l10n.tr('撤销', 'Undo'),
          onPressed: () {
            try {
              workspace.relocateEntry(currentTargetPath, sourcePath);
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.tr('撤销失败：$error', 'Undo failed: $error'),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  bool _hasDirtyDescendant(String directory) =>
      workspace.hasDirtyFileDescendant(directory);

  Future<void> _createEntry(
    BuildContext context, {
    required String directory,
    required WorkspaceEntryType type,
  }) async {
    final l10n = context.l10n;
    final name = await _askForName(
      context,
      title: type == WorkspaceEntryType.file
          ? l10n.tr('新建文件', 'New file')
          : l10n.tr('新建文件夹', 'New folder'),
      hint: type == WorkspaceEntryType.file
          ? l10n.tr('例如 home_screen.dart', 'For example: home_screen.dart')
          : l10n.tr('例如 screens', 'For example: screens'),
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
      title: context.l10n.tr('重命名', 'Rename'),
      hint: entry.name,
      initialValue: entry.name,
    );
    if (name == null || name == entry.name) return;
    _runAction(context, () => workspace.renameEntry(entry.path, name));
  }

  Future<void> _delete(BuildContext context, WorkspaceEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tr('删除 ${entry.name}？', 'Delete ${entry.name}?')),
        content: Text(
          entry.isDirectory
              ? l10n.tr(
                  '这个文件夹以及里面的文件都会从当前练习 Workspace 删除。',
                  'This folder and all files inside it will be deleted from the current Workspace.',
                )
              : l10n.tr(
                  '这个文件会从当前练习 Workspace 删除。',
                  'This file will be deleted from the current Workspace.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.tr('删除', 'Delete')),
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
    final l10n = context.l10n;

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onChanged: (value) => currentValue = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, currentValue.trim()),
            child: Text(l10n.tr('确定', 'OK')),
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
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
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
          color: highlighted ? palette.selection : palette.surfaceRaised,
          padding: const EdgeInsets.only(left: 10, right: 4),
          child: Row(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 15,
                color: WorkspaceFileExplorer._folderColor,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'PROJECT FILES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .7,
                    color: palette.text,
                  ),
                ),
              ),
              if (workspace.isDirty)
                Tooltip(
                  message: l10n.tr(
                    '${workspace.changes.length} 个 Workspace 修改',
                    '${workspace.changes.length} Workspace changes',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Icon(
                      Icons.circle,
                      size: 7,
                      color: palette.accent,
                    ),
                  ),
                ),
              _HeaderAction(
                tooltip: l10n.tr('新建文件', 'New file'),
                icon: Icons.note_add_outlined,
                onPressed: onCreateFile,
              ),
              _HeaderAction(
                tooltip: l10n.tr('新建文件夹', 'New folder'),
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
    final palette = WorkbenchPalette.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 29, height: 29),
      splashRadius: 15,
      icon: Icon(icon, size: 16, color: palette.muted),
    );
  }
}

class _EntryLabel extends StatelessWidget {
  const _EntryLabel({required this.entry, required this.dirty});

  final WorkspaceEntry entry;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: palette.text),
          ),
        ),
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.circle, size: 7, color: palette.accent),
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
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.tr('更多', 'More'),
      color: palette.surfaceRaised,
      padding: EdgeInsets.zero,
      iconSize: 17,
      icon: Icon(Icons.more_vert, color: palette.muted),
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
          PopupMenuItem(
            value: 'file',
            child: Text(l10n.tr('新建文件', 'New file')),
          ),
        if (onCreateDirectory != null)
          PopupMenuItem(
            value: 'folder',
            child: Text(l10n.tr('新建文件夹', 'New folder')),
          ),
        PopupMenuItem(
          value: 'rename',
          child: Text(l10n.tr('重命名', 'Rename')),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Text(l10n.tr('删除', 'Delete')),
        ),
      ],
    );
  }
}
