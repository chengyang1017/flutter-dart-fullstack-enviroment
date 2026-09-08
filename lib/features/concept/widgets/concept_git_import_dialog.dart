import 'package:flutter/material.dart';

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
  final projectPathController = TextEditingController();
  final secretNameController = TextEditingController();
  final secretValueController = TextEditingController();
  final usernameController = TextEditingController();

  bool showSecret = false;
  String? errorText;

  @override
  void dispose() {
    repositoryController.dispose();
    branchController.dispose();
    projectPathController.dispose();
    secretNameController.dispose();
    secretValueController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  void _submit() {
    final repository = repositoryController.text.trim();
    final branch = branchController.text.trim();
    final projectPath = projectPathController.text.trim();
    final secretName = secretNameController.text.trim();
    final secretValue = secretValueController.text;
    final username = usernameController.text.trim();

    if (repository.isEmpty) {
      setState(() => errorText = '请输入 Git repository URL。');
      return;
    }
    if (branch.isEmpty) {
      setState(() => errorText = '请输入 Git branch。');
      return;
    }
    if (secretValue.isNotEmpty && secretName.isEmpty) {
      setState(() => errorText = '输入 Token 时必须填写 Secret name。');
      return;
    }

    Navigator.of(context).pop(
      ConceptGitImportRequest(
        repositoryUrl: repository,
        branch: branch,
        projectPath: projectPath.isEmpty ? null : projectPath,
        secretName: secretName.isEmpty ? null : secretName,
        secretValue: secretValue.isEmpty ? null : secretValue,
        username: username.isEmpty ? null : username,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      key: const ValueKey('concept-git-import-dialog'),
      title: const Text('从 Git 打开 Flutter 项目'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '可以直接输入 monorepo。系统会扫描可运行 Flutter App；如果只有一个，会自动选择它。',
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('concept-git-branch'),
                      controller: branchController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: const ValueKey('concept-git-project-path'),
                      controller: projectPathController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Flutter 子项目路径（可选）',
                        hintText: 'apps/mobile-flutter',
                        helperText: '留空时自动检测唯一 Flutter App',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Git 凭据（公开仓库可全部留空）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('concept-git-secret-name'),
                controller: secretNameController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Secret name（可选）',
                  hintText: 'GITHUB_TOKEN',
                  border: OutlineInputBorder(),
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
                  labelText: 'Token / password（可选）',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: showSecret ? '隐藏凭据' : '显示凭据',
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
                decoration: const InputDecoration(
                  labelText: 'Username（通常可留空）',
                  border: OutlineInputBorder(),
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
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('concept-git-import-submit'),
          onPressed: _submit,
          icon: const Icon(Icons.download_rounded),
          label: const Text('拉取并打开'),
        ),
      ],
    );
  }
}
