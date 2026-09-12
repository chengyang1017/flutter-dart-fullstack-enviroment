import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../models/workspace_project.dart';
import '../services/workspace_cloud_runtime.dart';
import '../services/workspace_storage_status_service.dart';

enum _OpenProjectAction { folder, zip }

enum _ProjectAction { keep, rename, delete }

class WorkspaceProjectBar extends StatelessWidget {
  const WorkspaceProjectBar({
    super.key,
    required this.projects,
    required this.activeProject,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    this.onOpenFolder,
    this.onImportZip,
    this.onCommit,
    this.onShare,
    this.onKeep,
    this.onGitSync,
  });

  final List<WorkspaceProject> projects;
  final WorkspaceProject activeProject;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onImportZip;
  final VoidCallback? onCommit;
  final VoidCallback? onShare;
  final VoidCallback? onKeep;
  final VoidCallback? onGitSync;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _projectSelector(context),
          const SizedBox(width: 6),
          _ProjectActionButton(
            key: const ValueKey('workspace-project-create'),
            tooltip: l10n.tr('新建 Flutter 项目', 'Create Flutter project'),
            icon: Icons.add_rounded,
            label: l10n.tr('新建', 'New'),
            onPressed: onCreate,
          ),
          const SizedBox(width: 4),
          _OpenProjectButton(
            key: const ValueKey('workspace-project-open'),
            onOpenFolder: onOpenFolder,
            onImportZip: onImportZip,
          ),
          const SizedBox(width: 4),
          _ProjectActionButton(
            key: const ValueKey('workspace-project-commit'),
            tooltip: l10n.tr(
              'Commit 当前修改为新的 Workspace 基线（不 Push）',
              'Commit current changes as a new Workspace baseline (no Push)',
            ),
            icon: Icons.commit_rounded,
            label: 'Commit',
            onPressed: onCommit,
          ),
          if (onGitSync != null) ...[
            const SizedBox(width: 4),
            _GitHubSyncButton(project: activeProject, onPressed: onGitSync!),
          ],
          if (WorkspaceCloudRuntime.enabled && onShare != null) ...[
            const SizedBox(width: 4),
            _ProjectActionButton(
              key: const ValueKey('workspace-project-share'),
              tooltip: l10n.tr(
                '生成当前 Workspace 的固定版本只读分享链接',
                'Create a versioned read-only share link for this Workspace',
              ),
              icon: Icons.ios_share_rounded,
              label: l10n.tr('分享', 'Share'),
              onPressed: onShare,
            ),
          ],
          if (WorkspaceCloudRuntime.enabled) ...[
            const SizedBox(width: 4),
            const _CloudStorageStatusChip(),
          ],
          const SizedBox(width: 4),
          _ProjectMenu(
            project: activeProject,
            canDelete: projects.length > 1,
            onKeep: onKeep,
            onRename: onRename,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _projectSelector(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey('workspace-project-selector'),
      tooltip: _statusText(context, activeProject),
      color: palette.surfaceRaised,
      onSelected: (value) {
        if (value != activeProject.id) onSelect(value);
      },
      itemBuilder: (_) => projects
          .map(
            (project) => PopupMenuItem<String>(
              value: project.id,
              child: Row(
                children: [
                  Icon(
                    _projectIcon(project),
                    size: 17,
                    color: project.id == activeProject.id
                        ? palette.accent
                        : palette.muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (project.id == activeProject.id)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: palette.accent,
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Tooltip(
        message: _statusText(context, activeProject),
        child: Container(
          width: 220,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.surfaceRaised,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(_projectIcon(activeProject), size: 17, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activeProject.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _projectIcon(WorkspaceProject project) => switch (project.kind) {
        WorkspaceProjectKind.generatedFlutter => Icons.flutter_dash_rounded,
        WorkspaceProjectKind.importedFlutter => Icons.folder_zip_outlined,
        _ => Icons.folder_copy_outlined,
      };

  String _statusText(BuildContext context, WorkspaceProject project) {
    final l10n = context.l10n;
    final identity = WorkspaceCloudRuntime.identity;
    final namespace = identity == null
        ? project.slug
        : '${identity.accountNamespace} / ${project.slug}';
    final storage = identity == null
        ? l10n.tr('浏览器本地保存', 'Browser local storage')
        : l10n.tr('云端保存', 'Cloud storage');

    if (project.kind == WorkspaceProjectKind.generatedFlutter) {
      final platforms = project.flutterPlatforms.map(_platformLabel).join(' · ');
      final projectType = platforms.isEmpty
          ? l10n.tr('Flutter 项目', 'Flutter project')
          : 'Flutter · $platforms';
      return '$namespace · $projectType · $storage';
    }
    if (project.kind == WorkspaceProjectKind.importedFlutter) {
      return '$namespace · ${l10n.tr('导入的 Flutter 项目', 'Imported Flutter project')} · $storage';
    }
    if (project.lifecycle == WorkspaceLifecycle.temporary) {
      return '$namespace · ${l10n.tr('临时练习', 'Temporary practice')} · $storage';
    }
    return '$namespace · Workspace · $storage';
  }

  String _platformLabel(String platform) => switch (platform) {
        'android' => 'Android',
        'ios' => 'iOS',
        'web' => 'Web',
        'windows' => 'Windows',
        'macos' => 'macOS',
        'linux' => 'Linux',
        _ => platform,
      };
}

class _GitHubSyncButton extends StatefulWidget {
  const _GitHubSyncButton({required this.project, required this.onPressed});

  final WorkspaceProject project;
  final VoidCallback onPressed;

  @override
  State<_GitHubSyncButton> createState() => _GitHubSyncButtonState();
}

class _GitHubSyncButtonState extends State<_GitHubSyncButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
    final remote = widget.project.gitRemote;
    final isBound = remote != null;

    late final String label;
    late final String tooltip;
    late final IconData leadingIcon;
    late final IconData trailingIcon;

    if (!isBound) {
      label = l10n.tr('GitHub · 未绑定', 'GitHub · Not connected');
      tooltip = l10n.tr('点击绑定 GitHub 仓库', 'Connect a GitHub repository');
      leadingIcon = Icons.link_rounded;
      trailingIcon = Icons.add_rounded;
    } else {
      final fullName = remote.repositoryFullName;
      final repositoryName = fullName == null
          ? _repositoryNameFromUrl(remote.repositoryUrl)
          : fullName.split('/').last;
      final identity = fullName ?? remote.repositoryUrl;
      final idText = remote.repositoryId == null
          ? ''
          : '\nRepository #${remote.repositoryId}';
      label = 'GitHub · $repositoryName';
      tooltip = 'GitHub\n$identity\n${remote.branch}$idText\n${l10n.tr('点击打开同步中心', 'Open sync center')}';
      leadingIcon = Icons.sync_rounded;
      trailingIcon = Icons.keyboard_arrow_down_rounded;
    }

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          key: const ValueKey('workspace-github-sync'),
          borderRadius: BorderRadius.circular(7),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 36,
            constraints: const BoxConstraints(maxWidth: 190),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hovered ? palette.selection : palette.surfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(leadingIcon, size: 16, color: palette.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 15, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _repositoryNameFromUrl(String value) {
    var source = value.trim().replaceAll('\\', '/');
    while (source.endsWith('/')) {
      source = source.substring(0, source.length - 1);
    }
    if (source.toLowerCase().endsWith('.git')) {
      source = source.substring(0, source.length - 4);
    }
    final slash = source.lastIndexOf('/');
    final colon = source.lastIndexOf(':');
    final split = slash > colon ? slash : colon;
    return split >= 0 && split + 1 < source.length
        ? source.substring(split + 1)
        : source;
  }
}

class _CloudStorageStatusChip extends StatefulWidget {
  const _CloudStorageStatusChip();

  @override
  State<_CloudStorageStatusChip> createState() => _CloudStorageStatusChipState();
}

class _CloudStorageStatusChipState extends State<_CloudStorageStatusChip> {
  final WorkspaceStorageStatusService _service =
      const WorkspaceStorageStatusService();
  WorkspaceStorageStatus? _status;
  Object? _error;
  bool _loading = true;
  bool _hovered = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!WorkspaceCloudRuntime.enabled) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _service.load();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
    final status = _status;
    final available = status?.available == true;
    final label = _loading
        ? 'Cloud…'
        : available
            ? '${_formatStorageBytes(status!.usedBytes)} / ${_formatStorageBytes(status.totalBytes)}'
            : 'Cloud';

    final tooltip = _loading
        ? l10n.tr('正在读取 Railway Volume 容量…', 'Reading Railway Volume capacity…')
        : available
            ? 'Railway Volume\n${l10n.tr('已用', 'Used')}：${_formatStorageBytes(status!.usedBytes)}\n${l10n.tr('可用', 'Available')}：${_formatStorageBytes(status.availableBytes)}\n${l10n.tr('总量', 'Total')}：${_formatStorageBytes(status.totalBytes)}\n${l10n.tr('点击刷新', 'Click to refresh')}'
            : _error != null
                ? l10n.tr(
                    'Railway 容量读取失败：$_error\n点击重试',
                    'Failed to read Railway capacity: $_error\nClick to retry',
                  )
                : l10n.tr(
                    'Railway 容量暂不可用\n点击重试',
                    'Railway capacity is unavailable\nClick to retry',
                  );

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: _loading ? null : () => unawaited(_refresh()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: _hovered ? palette.selection : palette.surfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available ? Icons.cloud_done_outlined : Icons.cloud_queue_outlined,
                  size: 15,
                  color: available ? palette.accent : palette.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatStorageBytes(int? bytes) {
    if (bytes == null || bytes < 0) return '—';
    const kib = 1024.0;
    const mib = kib * 1024;
    const gib = mib * 1024;
    final value = bytes.toDouble();
    if (value >= gib) {
      final gb = value / gib;
      return '${gb >= 10 ? gb.toStringAsFixed(1) : gb.toStringAsFixed(2)} GB';
    }
    if (value >= mib) return '${(value / mib).toStringAsFixed(0)} MB';
    if (value >= kib) return '${(value / kib).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}

class _OpenProjectButton extends StatefulWidget {
  const _OpenProjectButton({
    super.key,
    required this.onOpenFolder,
    required this.onImportZip,
  });

  final VoidCallback? onOpenFolder;
  final VoidCallback? onImportZip;

  @override
  State<_OpenProjectButton> createState() => _OpenProjectButtonState();
}

class _OpenProjectButtonState extends State<_OpenProjectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
    final enabled = widget.onOpenFolder != null || widget.onImportZip != null;

    return PopupMenuButton<_OpenProjectAction>(
      enabled: enabled,
      color: palette.surfaceRaised,
      tooltip: l10n.tr('打开 Flutter 项目', 'Open Flutter project'),
      onSelected: (action) {
        if (action == _OpenProjectAction.folder) {
          widget.onOpenFolder?.call();
        } else {
          widget.onImportZip?.call();
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<_OpenProjectAction>>[
        PopupMenuItem<_OpenProjectAction>(
          value: _OpenProjectAction.folder,
          enabled: widget.onOpenFolder != null,
          child: Row(
            children: [
              Icon(Icons.folder_open_rounded, size: 17, color: palette.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.tr('打开项目文件夹', 'Open project folder'),
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.tr(
                        '选择包含 pubspec.yaml 的 Flutter 根目录',
                        'Choose a Flutter root containing pubspec.yaml',
                      ),
                      style: TextStyle(color: palette.muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<_OpenProjectAction>(
          value: _OpenProjectAction.zip,
          enabled: widget.onImportZip != null,
          child: Row(
            children: [
              Icon(Icons.archive_outlined, size: 17, color: palette.muted),
              const SizedBox(width: 9),
              Text(
                l10n.tr('导入 ZIP', 'Import ZIP'),
                style: TextStyle(
                  color: palette.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: enabled && _hovered ? palette.selection : palette.surfaceRaised,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 16,
                color: enabled
                    ? palette.text
                    : palette.muted.withValues(alpha: .45),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.tr('打开', 'Open'),
                style: TextStyle(
                  color: enabled
                      ? palette.text
                      : palette.muted.withValues(alpha: .45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: enabled
                    ? palette.muted
                    : palette.muted.withValues(alpha: .35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectActionButton extends StatefulWidget {
  const _ProjectActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_ProjectActionButton> createState() => _ProjectActionButtonState();
}

class _ProjectActionButtonState extends State<_ProjectActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: enabled && _hovered ? palette.selection : palette.surfaceRaised,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: enabled
                      ? palette.muted
                      : palette.muted.withValues(alpha: .38),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: enabled
                        ? palette.text
                        : palette.muted.withValues(alpha: .38),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({
    required this.project,
    required this.canDelete,
    required this.onKeep,
    required this.onRename,
    required this.onDelete,
  });

  final WorkspaceProject project;
  final bool canDelete;
  final VoidCallback? onKeep;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
    return PopupMenuButton<_ProjectAction>(
      key: const ValueKey('workspace-project-more'),
      color: palette.surfaceRaised,
      tooltip: l10n.tr('项目操作', 'Project actions'),
      onSelected: (action) {
        switch (action) {
          case _ProjectAction.keep:
            onKeep?.call();
            break;
          case _ProjectAction.rename:
            onRename();
            break;
          case _ProjectAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (_) => [
        if (project.lifecycle == WorkspaceLifecycle.temporary)
          PopupMenuItem(
            value: _ProjectAction.keep,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              iconColor: palette.muted,
              textColor: palette.text,
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(l10n.tr('保留项目', 'Keep project')),
            ),
          ),
        PopupMenuItem(
          value: _ProjectAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: palette.muted,
            textColor: palette.text,
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.tr('重命名', 'Rename')),
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.delete,
          enabled: canDelete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: canDelete
                ? palette.muted
                : palette.muted.withValues(alpha: .38),
            textColor: canDelete
                ? palette.text
                : palette.muted.withValues(alpha: .38),
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.tr('删除', 'Delete')),
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: palette.border),
        ),
        child: Icon(Icons.more_horiz_rounded, size: 18, color: palette.muted),
      ),
    );
  }
}
