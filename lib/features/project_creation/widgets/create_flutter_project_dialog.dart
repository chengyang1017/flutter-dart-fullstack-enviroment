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
  final _nameController = TextEditingController(
    text: 'my_app',
  );

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
      icon: Icons.android,
    ),
    _PlatformOption(
      id: 'ios',
      label: 'iOS',
      icon: Icons.phone_iphone,
    ),
    _PlatformOption(
      id: 'web',
      label: 'Web',
      icon: Icons.language,
    ),
    _PlatformOption(
      id: 'windows',
      label: 'Windows',
      icon: Icons.desktop_windows,
    ),
    _PlatformOption(
      id: 'macos',
      label: 'macOS',
      icon: Icons.laptop_mac,
    ),
    _PlatformOption(
      id: 'linux',
      label: 'Linux',
      icon: Icons.computer,
    ),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _create() {
    final l10n = context.l10n;
    final name = _nameController.text.trim();

    if (!RegExp(
      r'^[a-z][a-z0-9_]*$',
    ).hasMatch(name)) {
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
        platforms: Set<String>.of(
          _platforms,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(
        l10n.tr('创建 Flutter 项目', 'Create Flutter project'),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Project name',
                hintText: 'my_app',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 20),
            Text(
              'Platforms',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availablePlatforms.map(
                (platform) {
                  final selected = _platforms.contains(
                    platform.id,
                  );

                  return FilterChip(
                    selected: selected,
                    avatar: Icon(
                      platform.icon,
                      size: 18,
                    ),
                    label: Text(
                      platform.label,
                    ),
                    onSelected: (value) {
                      setState(() {
                        _error = null;

                        if (value) {
                          _platforms.add(
                            platform.id,
                          );
                        } else {
                          _platforms.remove(
                            platform.id,
                          );
                        }
                      });
                    },
                  );
                },
              ).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(
                height: 14,
              ),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: _create,
          child: Text(l10n.tr('创建', 'Create')),
        ),
      ],
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
