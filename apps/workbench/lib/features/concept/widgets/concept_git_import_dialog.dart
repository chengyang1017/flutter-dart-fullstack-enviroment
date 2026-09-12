import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../services/concept_git_import_service.dart';

Future<ConceptGitImportRequest?> showConceptGitImportDialog(
  BuildContext context,
) {
  return showDialog<ConceptGitImportRequest>(
    context: context,
    builder: (_) => const ConceptGitImportDialog(),
  );
}

class ConceptGitImportDialog extends StatefulWidget {
  const ConceptGitImportDialog({super.key});

  @override
  State<ConceptGitImportDialog> createState() => _ConceptGitImportDialogState();
}

class _ConceptGitImportDialogState extends State<ConceptGitImportDialog> {
  final repositoryController = TextEditingController();
  final branchController = TextEditingController(text: 'main');
  final secretNameController = TextEditingController();
  final secretValueController = TextEditingController();
  final usernameController = TextEditingController();

  bool showSecret = false;
  String? errorText;

  @override
  void dispose() {
    repositoryController.dispose();
    branchController.dispose();
    secretNameController.dispose();
    secretValueController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = context.l10n;
    final repository = repositoryController.text.trim();
    final branch = branchController.text.trim();
    final secretName = secretNameController.text.trim();
    final secretValue = secretValueController.text;
    final username = usernameController.text.trim();

    if (repository.isEmpty) {
      setState(() => errorText = l10n.tr(
            '请输入 Git repository URL。',
            'Enter a Git repository URL.',
          ));
      return;
    }
    if (branch.isEmpty) {
      setState(() => errorText = l10n.tr(
            '请输入 Git branch。',
            'Enter a Git branch.',
          ));
      return;
    }
    if (secretValue.isNotEmpty && secretName.isEmpty) {
      setState(() => errorText = l10n.tr(
            '输入 Token 时必须填写 Secret name。',
            'A Secret name is required when a token is provided.',
          ));
      return;
    }

    Navigator.of(context).pop(
      ConceptGitImportRequest(
        repositoryUrl: repository,
        branch: branch,
        secretName: secretName.isEmpty ? null : secretName,
        secretValue: secretValue.isEmpty ? null : secretValue,
        username: username.isEmpty ? null : username,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AlertDialog(
      key: const ValueKey('concept-git-import-dialog'),
      title: Text(l10n.tr(
        '从 Git 打开 Flutter 项目',
        'Open Flutter project from Git',
      )),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tr(
                  '直接输入仓库即可。系统会自动扫描可运行 Flutter App：只有一个时直接打开；检测到多个时再让你选择，不需要手写 monorepo 子项目路径。',
                  'Enter the repository URL. The system will scan for runnable Flutter apps automatically: one app opens directly; multiple apps are shown for selection, so you do not need to type a monorepo subproject path.',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('concept-git-repository-url'),
                controller: repositoryController,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Repository URL',
                  hintText: 'https://github.com/chengyang1017/glyphora.git',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('concept-git-branch'),
                controller: branchController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Branch',
                  helperText: l10n.tr(
                    '默认 main；Flutter 子项目由系统自动检测',
                    'Defaults to main; Flutter subprojects are detected automatically.',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.tr(
                  'Git 凭据（公开仓库可全部留空）',
                  'Git credentials (leave blank for public repositories)',
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('concept-git-secret-name'),
                controller: secretNameController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.tr('Secret name（可选）', 'Secret name (optional)'),
                  hintText: 'GITHUB_TOKEN',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('concept-git-secret-value'),
                controller: secretValueController,
                obscureText: !showSecret,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.tr(
                    'Token / password（可选）',
                    'Token / password (optional)',
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: showSecret
                        ? l10n.tr('隐藏凭据', 'Hide credentials')
                        : l10n.tr('显示凭据', 'Show credentials'),
                    onPressed: () => setState(() => showSecret = !showSecret),
                    icon: Icon(
                      showSecret ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('concept-git-username'),
                controller: usernameController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l10n.tr(
                    'Username（通常可留空）',
                    'Username (usually optional)',
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  key: const ValueKey('concept-git-import-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton.icon(
          key: const ValueKey('concept-git-import-submit'),
          onPressed: _submit,
          icon: const Icon(Icons.download_rounded),
          label: Text(l10n.tr('扫描并打开', 'Scan and open')),
        ),
      ],
    );
  }
}
