import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

class CreateFlutterProjectRequest {
  const CreateFlutterProjectRequest({
    required this.projectName,
    required this.platforms,
  });

  final String projectName;
  final Set<String> platforms;
}

Future<CreateFlutterProjectRequest?> showCreateFlutterProjectDialog(
  BuildContext context,
) {
  return showDialog<CreateFlutterProjectRequest>(
    context: context,
    builder: (_) => const _CreateFlutterProjectDialog(),
  );
}

class _CreateFlutterProjectDialog extends StatefulWidget {
  const _CreateFlutterProjectDialog();

  @override
  State<_CreateFlutterProjectDialog> createState() =>
      _CreateFlutterProjectDialogState();
}

class _CreateFlutterProjectDialogState
    extends State<_CreateFlutterProjectDialog> {
  final _nameController = TextEditingController(text: 'my_app');

  final Set<String> _platforms = {
    'android',
    'ios',
    'web',
    'windows',
    'macos',
    'linux',
  };

  String? _error;

  static const _availablePlatforms = <_PlatformOption>[
    _PlatformOption(
      id: 'android',
      label: 'Android',
      icon: Icons.android_rounded,
    ),
    _PlatformOption(
      id: 'ios',
      label: 'iOS',
      icon: Icons.phone_iphone_rounded,
    ),
    _PlatformOption(
      id: 'web',
      label: 'Web',
      icon: Icons.language_rounded,
    ),
    _PlatformOption(
      id: 'windows',
      label: 'Windows',
      icon: Icons.desktop_windows_rounded,
    ),
    _PlatformOption(
      id: 'macos',
      label: 'macOS',
      icon: Icons.laptop_mac_rounded,
    ),
    _PlatformOption(
      id: 'linux',
      label: 'Linux',
      icon: Icons.computer_rounded,
    ),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _togglePlatform(String id) {
    setState(() {
      _error = null;
      if (_platforms.contains(id)) {
        _platforms.remove(id);
      } else {
        _platforms.add(id);
      }
    });
  }

  void _create() {
    final l10n = context.l10n;
    final name = _nameController.text.trim();

    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      setState(() {
        _error = l10n.tr(
          '项目名称只能使用小写字母、数字和下划线，例如 my_app',
          'Project names can contain only lowercase letters, numbers, and underscores, for example my_app.',
        );
      });
      return;
    }

    if (_platforms.isEmpty) {
      setState(() {
        _error = l10n.tr('至少选择一个平台', 'Select at least one platform.');
      });
      return;
    }

    Navigator.of(context).pop(
      CreateFlutterProjectRequest(
        projectName: name,
        platforms: Set<String>.of(_platforms),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      titlePadding: const EdgeInsets.fromLTRB(28, 26, 28, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.add_box_outlined,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('创建 Flutter 项目', 'Create Flutter project'),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.tr(
                    '选择项目名称和目标平台。',
                    'Choose a project name and target platforms.',
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 570,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.tr('项目名称', 'Project name'),
                hintText: 'my_app',
                prefixIcon: const Icon(Icons.folder_outlined),
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  l10n.tr('目标平台', 'Target platforms'),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.tr(
                    '已选择 ${_platforms.length}',
                    '${_platforms.length} selected',
                  ),
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tr(
                '点击卡片切换平台；至少保留一个。',
                'Click a card to toggle it; keep at least one selected.',
              ),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 20) / 3
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _availablePlatforms.map((platform) {
                    final selected = _platforms.contains(platform.id);
                    return SizedBox(
                      width: itemWidth,
                      child: _PlatformChoice(
                        option: platform,
                        selected: selected,
                        onTap: () => _togglePlatform(platform.id),
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: scheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(l10n.tr('创建项目', 'Create project')),
        ),
      ],
    );
  }
}

class _PlatformChoice extends StatelessWidget {
  const _PlatformChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _PlatformOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: option.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primaryContainer.withValues(alpha: 0.68)
                  : scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.primary.withValues(alpha: 0.12)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    option.icon,
                    size: 19,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: scheme.onPrimary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformOption {
  const _PlatformOption({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}
