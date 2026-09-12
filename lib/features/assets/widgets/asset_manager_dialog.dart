import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_entry.dart';
import '../services/asset_workspace_service.dart';

Future<void> showAssetManagerDialog(
  BuildContext context, {
  required WorkspaceController workspace,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AssetManagerDialog(workspace: workspace),
  );
}

class AssetManagerDialog extends StatefulWidget {
  const AssetManagerDialog({super.key, required this.workspace});

  final WorkspaceController workspace;

  @override
  State<AssetManagerDialog> createState() => _AssetManagerDialogState();
}

class _AssetManagerDialogState extends State<AssetManagerDialog> {
  late final AssetWorkspaceService service;
  final TextEditingController _searchController = TextEditingController();

  String _targetFolder = AssetWorkspaceService.rootPath;
  bool _picking = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    service = AssetWorkspaceService(widget.workspace);
    widget.workspace.addListener(_workspaceChanged);
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_workspaceChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _workspaceChanged() {
    if (!mounted) return;
    final directories =
        service.assetDirectories.map((entry) => entry.path).toSet();
    if (!directories.contains(_targetFolder)) {
      _targetFolder = AssetWorkspaceService.rootPath;
    }
    setState(() {});
  }

  List<WorkspaceEntry> get _visibleAssets {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return service.assetFiles;
    return service.assetFiles
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.path.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final assets = _visibleAssets;
    final directories = service.assetDirectories;
    final imageCount = service.assetFiles.where(_isImage).length;

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1080,
          maxHeight: 780,
          minWidth: 320,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.perm_media_outlined,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assets',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.tr(
                            '资源界面化 · 系统自动维护 assets/ 与 pubspec.yaml',
                            'Visual asset management · assets/ and pubspec.yaml are maintained automatically',
                          ),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tr('关闭', 'Close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusChip(
                    icon: Icons.inventory_2_outlined,
                    label: l10n.tr(
                      '${service.assetFiles.length} 个资源',
                      '${service.assetFiles.length} assets',
                    ),
                  ),
                  _StatusChip(
                    icon: Icons.image_outlined,
                    label: l10n.tr(
                      '$imageCount 张图片',
                      '$imageCount images',
                    ),
                  ),
                  _StatusChip(
                    icon: service.isAssetsDeclared
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    label: service.isAssetsDeclared
                        ? l10n.tr(
                            'pubspec 已声明 assets/',
                            'assets/ declared in pubspec',
                          )
                        : l10n.tr(
                            '上传时自动写入 pubspec',
                            'pubspec will be updated on import',
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final folderPicker = _FolderPicker(
                    directories: directories,
                    value: _targetFolder,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _targetFolder = value);
                      }
                    },
                  );
                  final search = TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      hintText: l10n.tr(
                        '搜索资源名称或路径',
                        'Search asset name or path',
                      ),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.tr('清除', 'Clear'),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  );

                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('asset-create-folder'),
                        onPressed: _createFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: Text(l10n.tr('新建文件夹', 'New folder')),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('asset-upload-files'),
                        onPressed: _picking ? null : _pickFiles,
                        icon: _picking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _picking
                              ? l10n.tr('导入中…', 'Importing…')
                              : l10n.tr('导入资源', 'Import assets'),
                        ),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        folderPicker,
                        const SizedBox(height: 8),
                        search,
                        const SizedBox(height: 8),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(width: 230, child: folderPicker),
                      const SizedBox(width: 10),
                      Expanded(child: search),
                      const SizedBox(width: 10),
                      actions,
                    ],
                  );
                },
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _message!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: assets.isEmpty
                  ? _EmptyAssets(
                      hasAnyAsset: service.assetFiles.isNotEmpty,
                      onImport: _picking ? null : _pickFiles,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 940
                            ? 4
                            : constraints.maxWidth >= 680
                                ? 3
                                : constraints.maxWidth >= 430
                                    ? 2
                                    : 1;
                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 250,
                          ),
                          itemCount: assets.length,
                          itemBuilder: (context, index) => _AssetCard(
                            entry: assets[index],
                            onRename: () => _renameAsset(assets[index]),
                            onDelete: () => _deleteAsset(assets[index]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final l10n = context.l10n;
    setState(() {
      _picking = true;
      _message = null;
    });

    try {
      service.ensureAssetsReady();
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      var imported = 0;
      final skipped = <String>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) {
          skipped.add(
            l10n.tr(
              '${file.name}（无法读取内容）',
              '${file.name} (content could not be read)',
            ),
          );
          continue;
        }
        try {
          service.addBinaryAsset(
            parentPath: _targetFolder,
            name: file.name,
            bytes: bytes,
          );
          imported++;
        } catch (error) {
          skipped.add('${file.name} ($error)');
        }
      }

      if (mounted) {
        setState(() {
          _message = skipped.isEmpty
              ? l10n.tr(
                  '已导入 $imported 个资源，并确认 pubspec.yaml 已注册 assets/。',
                  'Imported $imported assets and confirmed that assets/ is registered in pubspec.yaml.',
                )
              : l10n.tr(
                  '已导入 $imported 个；跳过 ${skipped.length} 个：${skipped.join('、')}',
                  'Imported $imported; skipped ${skipped.length}: ${skipped.join(', ')}',
                );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = l10n.tr(
            '导入失败：$error',
            'Import failed: $error',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _createFolder() async {
    final l10n = context.l10n;
    final name = await _askForName(
      title: l10n.tr('新建 Assets 文件夹', 'New Assets folder'),
      hint: l10n.tr(
        '例如 images、icons、fonts',
        'For example: images, icons, fonts',
      ),
    );
    if (name == null) return;

    try {
      final path = service.createFolder(_targetFolder, name);
      if (mounted) {
        setState(() {
          _targetFolder = path;
          _message = l10n.tr('已创建 $path', 'Created $path');
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _renameAsset(WorkspaceEntry entry) async {
    final l10n = context.l10n;
    final name = await _askForName(
      title: l10n.tr('重命名资源', 'Rename asset'),
      hint: entry.name,
      initialValue: entry.name,
    );
    if (name == null || name == entry.name) return;

    try {
      service.renameAsset(entry.path, name);
      if (mounted) {
        setState(
          () => _message = l10n.tr(
            '已重命名为 $name',
            'Renamed to $name',
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _deleteAsset(WorkspaceEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tr('删除 ${entry.name}？', 'Delete ${entry.name}?')),
        content: Text(
          l10n.tr(
            '将从 Workspace 删除 ${entry.path}。',
            '${entry.path} will be deleted from the Workspace.',
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
    if (confirmed != true) return;

    try {
      service.deleteAsset(entry.path);
      if (mounted) {
        setState(
          () => _message = l10n.tr(
            '已删除 ${entry.path}',
            'Deleted ${entry.path}',
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<String?> _askForName({
    required String title,
    required String hint,
    String? initialValue,
  }) async {
    final l10n = context.l10n;
    var value = initialValue ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onChanged: (next) => value = next,
          onFieldSubmitted: (next) => Navigator.pop(context, next.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value.trim()),
            child: Text(l10n.tr('确定', 'OK')),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return null;
    if (result.contains('/') || result.contains('\\')) {
      setState(
        () => _message = l10n.tr(
          '名称不能包含路径分隔符。',
          'The name cannot contain path separators.',
        ),
      );
      return null;
    }
    return result.trim();
  }

  bool _isImage(WorkspaceEntry entry) {
    final extension = _extension(entry.name);
    return const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp'}
        .contains(extension);
  }
}

class _FolderPicker extends StatelessWidget {
  const _FolderPicker({
    required this.directories,
    required this.value,
    required this.onChanged,
  });

  final List<WorkspaceEntry> directories;
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final paths = directories.map((entry) => entry.path).toList();
    if (!paths.contains(AssetWorkspaceService.rootPath)) {
      paths.insert(0, AssetWorkspaceService.rootPath);
    }

    return DropdownButtonFormField<String>(
      value: paths.contains(value) ? value : AssetWorkspaceService.rootPath,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.l10n.tr('导入到', 'Import to'),
        isDense: true,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.folder_outlined, size: 19),
      ),
      items: paths
          .map(
            (path) => DropdownMenuItem<String>(
              value: path,
              child: Text('$path/', overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.entry,
    required this.onRename,
    required this.onDelete,
  });

  final WorkspaceEntry entry;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final image = _isImageEntry(entry);

    return Card(
      key: ValueKey('asset-card-${entry.path}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: image && entry.isBinary
                  ? Image.memory(
                      entry.bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _AssetTypeIcon(entry: entry),
                    )
                  : _AssetTypeIcon(entry: entry),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_assetKindLabel(context, entry)} · ${_formatBytes(entry.bytes.length)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: l10n.tr('复制资源路径', 'Copy asset path'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: entry.path));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                l10n.tr(
                                  '已复制 ${entry.path}',
                                  'Copied ${entry.path}',
                                ),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.content_copy_rounded, size: 17),
                    ),
                    if (image)
                      IconButton(
                        tooltip: 'Copy Image.asset(...)',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: "Image.asset('${entry.path}')"),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  l10n.tr(
                                    '已复制 Image.asset(...)',
                                    'Copied Image.asset(...)',
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.code_rounded, size: 18),
                      ),
                    IconButton(
                      tooltip: l10n.tr('重命名', 'Rename'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onRename,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: l10n.tr('删除', 'Delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetTypeIcon extends StatelessWidget {
  const _AssetTypeIcon({required this.entry});

  final WorkspaceEntry entry;

  @override
  Widget build(BuildContext context) {
    final icon = switch (_assetKindId(entry)) {
      'image' => Icons.image_outlined,
      'font' => Icons.font_download_outlined,
      'audio' => Icons.audio_file_outlined,
      'video' => Icons.video_file_outlined,
      'data' => Icons.data_object_rounded,
      _ => Icons.insert_drive_file_outlined,
    };
    return Center(child: Icon(icon, size: 52));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyAssets extends StatelessWidget {
  const _EmptyAssets({required this.hasAnyAsset, required this.onImport});

  final bool hasAnyAsset;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 58),
              const SizedBox(height: 14),
              Text(
                hasAnyAsset
                    ? l10n.tr('没有匹配的资源', 'No matching assets')
                    : l10n.tr('还没有 Assets', 'No assets yet'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 7),
              Text(
                hasAnyAsset
                    ? l10n.tr('换一个关键词试试。', 'Try another keyword.')
                    : l10n.tr(
                        '直接选择电脑上的图片、字体、JSON、音频等文件。系统会放进 assets/，并自动维护 pubspec.yaml。',
                        'Choose images, fonts, JSON, audio, and other files from your computer. They will be placed in assets/ and pubspec.yaml will be maintained automatically.',
                      ),
                textAlign: TextAlign.center,
              ),
              if (!hasAnyAsset) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    l10n.tr('导入第一个资源', 'Import first asset'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

bool _isImageEntry(WorkspaceEntry entry) {
  return const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp'}
      .contains(_extension(entry.name));
}

String _assetKindId(WorkspaceEntry entry) {
  final extension = _extension(entry.name);
  if (const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'}
      .contains(extension)) {
    return 'image';
  }
  if (const <String>{'ttf', 'otf', 'woff', 'woff2'}.contains(extension)) {
    return 'font';
  }
  if (const <String>{'mp3', 'wav', 'ogg', 'm4a', 'aac'}.contains(extension)) {
    return 'audio';
  }
  if (const <String>{'mp4', 'webm', 'mov', 'mkv'}.contains(extension)) {
    return 'video';
  }
  if (const <String>{'json', 'yaml', 'yml', 'csv', 'txt', 'xml'}
      .contains(extension)) {
    return 'data';
  }
  return 'file';
}

String _assetKindLabel(BuildContext context, WorkspaceEntry entry) {
  final l10n = context.l10n;
  return switch (_assetKindId(entry)) {
    'image' => l10n.tr('图片', 'Image'),
    'font' => l10n.tr('字体', 'Font'),
    'audio' => l10n.tr('音频', 'Audio'),
    'video' => l10n.tr('视频', 'Video'),
    'data' => l10n.tr('数据', 'Data'),
    _ => l10n.tr('文件', 'File'),
  };
}

String _extension(String name) {
  final index = name.lastIndexOf('.');
  if (index == -1 || index == name.length - 1) return '';
  return name.substring(index + 1).toLowerCase();
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
