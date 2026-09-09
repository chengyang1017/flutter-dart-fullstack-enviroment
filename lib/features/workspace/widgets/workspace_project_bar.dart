import 'dart:async';

import 'package:flutter/material.dart';

import '../models/workspace_project.dart';
import '../services/workspace_cloud_runtime.dart';
import '../services/workspace_storage_status_service.dart';

enum _OpenProjectAction { folder, zip }

enum _ProjectAction {
  keep,
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
    this.onOpenFolder,
    this.onImportZip,
    this.onCommit,
    this.onShare,
    this.onKeep,
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

  static const _surface = Color(0xff15191f);
  static const _surfaceHover = Color(0xff1c222b);
  static const _border = Color(0xff2b333e);
  static const _text = Color(0xffd7dde8);
  static const _muted = Color(0xff8f98a8);
  static const _accent = Color(0xff82aaff);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _projectSelector(context),
          const SizedBox(width: 6),
          _ProjectActionButton(
            key: const ValueKey('workspace-project-create'),
            tooltip: '新建 Flutter 项目',
            icon: Icons.add_rounded,
            label: '新建',
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
            tooltip: 'Commit 当前修改为新的 Workspace 基线（不 Push）',
            icon: Icons.commit_rounded,
            label: 'Commit',
            onPressed: onCommit,
          ),
          if (WorkspaceCloudRuntime.enabled && onShare != null) ...[
            const SizedBox(width: 4),
            _ProjectActionButton(
              key: const ValueKey('workspace-project-share'),
              tooltip: '生成当前 Workspace 的固定版本只读分享链接',
              icon: Icons.ios_share_rounded,
              label: '分享',
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
    return PopupMenuButton<String>(
      key: const ValueKey('workspace-project-selector'),
      tooltip: _statusText(activeProject),
      onSelected: (value) {
        if (value != activeProject.id) {
          onSelect(value);
        }
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
                    color: project.id == activeProject.id ? _accent : _muted,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (project.id == activeProject.id)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: _accent,
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Tooltip(
        message: _statusText(activeProject),
        child: Container(
          width: 220,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Icon(
                _projectIcon(activeProject),
                size: 17,
                color: _accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  activeProject.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _projectIcon(WorkspaceProject project) {
    return switch (project.kind) {
      WorkspaceProjectKind.generatedFlutter => Icons.flutter_dash_rounded,
      WorkspaceProjectKind.importedFlutter => Icons.folder_zip_outlined,
      _ => Icons.folder_copy_outlined,
    };
  }

  String _statusText(WorkspaceProject project) {
    final identity = WorkspaceCloudRuntime.identity;
    final namespace = identity == null
        ? project.slug
        : '${identity.accountNamespace} / ${project.slug}';
    final storage = identity == null ? '浏览器本地保存' : '云端保存';

    if (project.kind == WorkspaceProjectKind.generatedFlutter) {
      final platforms = project.flutterPlatforms.map(_platformLabel).join(' · ');
      final projectType = platforms.isEmpty ? 'Flutter 项目' : 'Flutter · $platforms';
      return '$namespace · $projectType · $storage';
    }
    if (project.kind == WorkspaceProjectKind.importedFlutter) {
      return '$namespace · 导入的 Flutter 项目 · $storage';
    }
    if (project.lifecycle == WorkspaceLifecycle.temporary) {
      return '$namespace · 临时练习 · $storage';
    }
    return '$namespace · Workspace · $storage';
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

class _CloudStorageStatusChip extends StatefulWidget {
  const _CloudStorageStatusChip();

  @override
  State<_CloudStorageStatusChip> createState() =>
      _CloudStorageStatusChipState();
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
    final status = _status;
    final available = status?.available == true;
    final label = _loading
        ? 'Cloud…'
        : available
            ? '${_formatStorageBytes(status!.usedBytes)} / '
                '${_formatStorageBytes(status.totalBytes)}'
            : 'Cloud';

    final tooltip = _loading
        ? '正在读取 Railway Volume 容量…'
        : available
            ? 'Railway Volume\n'
                '已用：${_formatStorageBytes(status!.usedBytes)}\n'
                '可用：${_formatStorageBytes(status.availableBytes)}\n'
                '总量：${_formatStorageBytes(status.totalBytes)}\n'
                '点击刷新'
            : _error != null
                ? 'Railway 容量读取失败：$_error\n点击重试'
                : 'Railway 容量暂不可用\n点击重试';

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
              color: _hovered
                  ? WorkspaceProjectBar._surfaceHover
                  : WorkspaceProjectBar._surface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: WorkspaceProjectBar._border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_queue_outlined,
                  size: 15,
                  color: available
                      ? WorkspaceProjectBar._accent
                      : WorkspaceProjectBar._muted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: WorkspaceProjectBar._text,
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
    final enabled = widget.onOpenFolder != null || widget.onImportZip != null;

    return PopupMenuButton<_OpenProjectAction>(
      enabled: enabled,
      tooltip: '打开 Flutter 项目',
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
          child: const Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 17,
                color: WorkspaceProjectBar._accent,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '打开项目文件夹',
                      style: TextStyle(
                        color: WorkspaceProjectBar._text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '选择包含 pubspec.yaml 的 Flutter 根目录',
                      style: TextStyle(
                        color: WorkspaceProjectBar._muted,
                        fontSize: 10.5,
                      ),
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
          child: const Row(
            children: [
              Icon(
                Icons.archive_outlined,
                size: 17,
                color: WorkspaceProjectBar._muted,
              ),
              SizedBox(width: 9),
              Text(
                '导入 ZIP',
                style: TextStyle(
                  color: WorkspaceProjectBar._text,
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
            color: enabled && _hovered
                ? WorkspaceProjectBar._surfaceHover
                : WorkspaceProjectBar._surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: WorkspaceProjectBar._border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_outlined,
                size: 16,
                color: enabled
                    ? WorkspaceProjectBar._text
                    : WorkspaceProjectBar._muted.withValues(alpha: .45),
              ),
              const SizedBox(width: 6),
              Text(
                '打开',
                style: TextStyle(
                  color: enabled
                      ? WorkspaceProjectBar._text
                      : WorkspaceProjectBar._muted.withValues(alpha: .45),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: enabled
                    ? WorkspaceProjectBar._muted
                    : WorkspaceProjectBar._muted.withValues(alpha: .35),
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
              color: enabled && _hovered
                  ? WorkspaceProjectBar._surfaceHover
                  : WorkspaceProjectBar._surface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: WorkspaceProjectBar._border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: enabled
                      ? WorkspaceProjectBar._muted
                      : WorkspaceProjectBar._muted.withValues(alpha: .38),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: enabled
                        ? WorkspaceProjectBar._text
                        : WorkspaceProjectBar._muted.withValues(alpha: .38),
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
    return PopupMenuButton<_ProjectAction>(
      key: const ValueKey('workspace-project-more'),
      tooltip: '项目操作',
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
          const PopupMenuItem(
            value: _ProjectAction.keep,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              iconColor: WorkspaceProjectBar._muted,
              textColor: WorkspaceProjectBar._text,
              leading: Icon(Icons.bookmark_add_outlined),
              title: Text(
                '保留项目',
                style: TextStyle(
                  color: WorkspaceProjectBar._text,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        const PopupMenuItem(
          value: _ProjectAction.rename,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: WorkspaceProjectBar._muted,
            textColor: WorkspaceProjectBar._text,
            leading: Icon(Icons.edit_outlined),
            title: Text(
              '重命名',
              style: TextStyle(
                color: WorkspaceProjectBar._text,
                fontSize: 13,
              ),
            ),
          ),
        ),
        PopupMenuItem(
          value: _ProjectAction.delete,
          enabled: canDelete,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            iconColor: canDelete
                ? WorkspaceProjectBar._muted
                : WorkspaceProjectBar._muted.withValues(alpha: .38),
            textColor: canDelete
                ? WorkspaceProjectBar._text
                : WorkspaceProjectBar._muted.withValues(alpha: .38),
            leading: const Icon(Icons.delete_outline),
            title: Text(
              '删除',
              style: TextStyle(
                color: canDelete
                    ? WorkspaceProjectBar._text
                    : WorkspaceProjectBar._muted.withValues(alpha: .38),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: WorkspaceProjectBar._surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: WorkspaceProjectBar._border),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: WorkspaceProjectBar._muted,
        ),
      ),
    );
  }
}
