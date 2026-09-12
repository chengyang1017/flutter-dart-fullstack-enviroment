import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

class ExportProjectGuideDialog extends StatelessWidget {
  const ExportProjectGuideDialog({
    super.key,
    required this.fileName,
    required this.projectType,
  });

  final String fileName;
  final String projectType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final requirements = _requirementsFor(context, projectType);
    final projectLabel = _projectLabel(context, projectType);

    return AlertDialog(
      key: const ValueKey('export-project-guide-dialog'),
      title: Text(l10n.tr('导出项目', 'Export project')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(projectLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr(
                        '你将下载一个练习包，不是完整 Flutter 项目。',
                        'You are downloading a practice package, not a complete Flutter project.',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.tr(
                        '它保存你的源码、配置和项目配方。Flutter 自动生成的工程文件和开发工具不会放进导出包。',
                        'It contains your source code, configuration, and project recipe. Flutter-generated project files and development tools are not included.',
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      fileName,
                      key: const ValueKey('export-practice-file-name'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.tr(
                  '在电脑上创建真实项目之前，需要准备：',
                  'Before creating the real project on your computer, prepare:',
                ),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final requirement in requirements)
                _RequirementTile(requirement: requirement),
              if (projectType == 'flutter-serverpod-mini') ...[
                const SizedBox(height: 6),
                _InfoNote(
                  key: const ValueKey('serverpod-database-note'),
                  icon: Icons.storage_outlined,
                  text: l10n.tr(
                    '如果这个 Serverpod 项目使用数据库，本地运行数据库时还需要 PostgreSQL，或者使用 Docker 提供 PostgreSQL。',
                    'If this Serverpod project uses a database, you also need PostgreSQL locally or a PostgreSQL instance provided through Docker.',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _InfoNote(
                key: const ValueKey('cli-beginner-note'),
                icon: Icons.school_outlined,
                text: l10n.tr(
                  '当前版本的本地项目创建器仍是命令行工具。你不需要理解 flutter create、pub get 等底层命令，但电脑必须先安装上面列出的开发工具。',
                  'The current local project creator is still a command-line tool. You do not need to understand lower-level commands such as flutter create or pub get, but the development tools listed above must be installed first.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tr(
                  '下载练习包本身不会修改或覆盖你电脑里的现有项目。',
                  'Downloading the practice package does not modify or overwrite existing projects on your computer.',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton.icon(
          key: const ValueKey('download-practice-package-button'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.tr('下载练习包', 'Download practice package')),
        ),
      ],
    );
  }

  List<_Requirement> _requirementsFor(BuildContext context, String type) {
    final l10n = context.l10n;
    final requirements = <_Requirement>[
      _Requirement(
        title: l10n.tr('Flutter SDK（必需）', 'Flutter SDK (required)'),
        description: l10n.tr(
          '用于创建、解析依赖和运行本地 Flutter 项目。Flutter SDK 已经包含 Dart SDK，不需要另外安装 Dart。',
          'Used to create the project, resolve dependencies, and run Flutter locally. The Flutter SDK already includes the Dart SDK.',
        ),
      ),
    ];

    if (type == 'flutter-dart-frog') {
      requirements.add(
        _Requirement(
          title: l10n.tr(
            'Dart Frog CLI（此项目需要）',
            'Dart Frog CLI (required for this project)',
          ),
          description: l10n.tr(
            '用于生成和运行 Dart Frog 后端。练习包保存后端源码，但不会携带 Dart Frog 开发工具。',
            'Used to generate and run the Dart Frog backend. The practice package contains backend source code but not the Dart Frog development tools.',
          ),
        ),
      );
    } else if (type == 'flutter-serverpod-mini') {
      requirements.add(
        _Requirement(
          title: l10n.tr(
            'Serverpod CLI（此项目需要）',
            'Serverpod CLI (required for this project)',
          ),
          description: l10n.tr(
            '用于生成 Serverpod 协议代码和运行后端。练习包保存 Serverpod 源码，但不会携带 Serverpod 开发工具。',
            'Used to generate Serverpod protocol code and run the backend. The practice package contains Serverpod source code but not the Serverpod development tools.',
          ),
        ),
      );
    }

    return requirements;
  }

  String _projectLabel(BuildContext context, String type) {
    final l10n = context.l10n;
    return switch (type) {
      'flutter-dart-frog' => 'Flutter + Dart Frog ${l10n.tr('项目', 'project')}',
      'flutter-serverpod-mini' => 'Flutter + Serverpod ${l10n.tr('项目', 'project')}',
      _ => l10n.tr('Flutter 项目', 'Flutter project'),
    };
  }
}

class _Requirement {
  const _Requirement({required this.title, required this.description});

  final String title;
  final String description;
}

class _RequirementTile extends StatelessWidget {
  const _RequirementTile({required this.requirement});

  final _Requirement requirement;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.download_for_offline_outlined, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requirement.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(requirement.description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
