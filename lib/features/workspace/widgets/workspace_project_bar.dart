import 'package:flutter/material.dart';

import '../models/workspace_project.dart';

enum _CompactProjectAction {
  rename,
  delete,
}

class WorkspaceProjectBar extends StatelessWidget {
  const WorkspaceProjectBar({
    super.key,
    required this.projects,
    required this.activeProject,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    this.onImport,
    this.onKeep,
  });

  final List<WorkspaceProject> projects;
  final WorkspaceProject activeProject;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onImport;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showStatus = constraints.maxWidth >= 700;
            final compactActions = constraints.maxWidth < 600;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.folder_copy_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const ValueKey('workspace-project-selector'),
                        value: activeProject.id,
                        isExpanded: true,
                        onChanged: (value) {
                          if (value != null && value != activeProject.id) {
                            onSelect(value);
                          }
                        },
                        items: projects
                            .map(
                              (project) => DropdownMenuItem<String>(
                                value: project.id,
                                child: Text(
                                  project.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('workspace-project-create'),
                    tooltip: '新建 Flutter 项目',
                    visualDensity: VisualDensity.compact,
                    onPressed: onCreate,
                    icon: const Icon(Icons.add, size: 19),
                  ),
                  IconButton(
                    key: const ValueKey('workspace-project-import'),
                    tooltip: '打开 Flutter 项目 ZIP',
                    visualDensity: VisualDensity.compact,
                    onPressed: onImport,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                  ),
                  if (activeProject.lifecycle == WorkspaceLifecycle.temporary)
                    IconButton(
                      key: const ValueKey('workspace-project-keep'),
                      tooltip: '保留当前临时练习',
                      visualDensity: VisualDensity.compact,
                      onPressed: onKeep,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    ),
                  if (compactActions)
                    _CompactProjectMenu(
                      canDelete: projects.length > 1,
                      onRename: onRename,
                      onDelete: onDelete,
                    )
                  else ...[
                    IconButton(
                      key: const ValueKey('workspace-project-rename'),
                      tooltip: '重命名当前练习',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRename,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      key: const ValueKey('workspace-project-delete'),
                      tooltip: '删除当前本地练习',
                      visualDensity: VisualDensity.compact,
                      onPressed: projects.length > 1 ? onDelete : null,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                  if (showStatus) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _statusText(activeProject),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _statusText(WorkspaceProject project) {
    if (project.kind == WorkspaceProjectKind.generatedFlutter) {
      final platforms = project.flutterPlatforms.map(_platformLabel).join(' · ');
      return platforms.isEmpty
          ? 'Flutter 项目 · 浏览器本地保存'
          : 'Flutter · $platforms';
    }
    if (project.kind == WorkspaceProjectKind.importedFlutter) {
      return '已导入 Flutter Workspace · 浏览器本地保存';
    }
    if (project.lifecycle == WorkspaceLifecycle.temporary) {
      return '临时练习 · 浏览器自动保存';
    }
    return '已保留 Workspace · 浏览器本地保存';
  }

  String _platformLabel(String platform) {
    return switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'web' => 'Web',
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => platform,
    };
  }
}

class _CompactProjectMenu extends StatelessWidget {
  const _CompactProjectMenu({
    required this.canDelete,
    required this.onRename,
    required this.onDelete,
  });

  final bool canDelete;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CompactProjectAction>(
      key: const ValueKey('workspace-project-more'),
      tooltip: '更多项目操作',
      onSelected: (action) {
        switch (action) {
          case _CompactProjectAction.rename:
            onRename();
            break;
          case _CompactProjectAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _CompactProjectAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('重命名'),
          ),
        ),
        PopupMenuItem(
          value: _CompactProjectAction.delete,
          enabled: canDelete,
          child: const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('删除'),
          ),
        ),
      ],
      icon: const Icon(Icons.more_horiz_rounded, size: 19),
    );
  }
}
