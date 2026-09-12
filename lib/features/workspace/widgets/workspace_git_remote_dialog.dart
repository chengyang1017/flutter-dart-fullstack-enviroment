import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../models/workspace_git_remote.dart';

class WorkspaceGitRemoteDialog extends StatefulWidget {
  const WorkspaceGitRemoteDialog({
    super.key,
    this.initialRemote,
  });

  final WorkspaceGitRemote? initialRemote;

  @override
  State<WorkspaceGitRemoteDialog> createState() =>
      _WorkspaceGitRemoteDialogState();
}

class _WorkspaceGitRemoteDialogState extends State<WorkspaceGitRemoteDialog> {
  late final TextEditingController _repositoryController;
  late final TextEditingController _remoteNameController;
  late final TextEditingController _branchController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final remote = widget.initialRemote;
    _repositoryController = TextEditingController(
      text: remote?.repositoryUrl ?? '',
    );
    _remoteNameController = TextEditingController(
      text: remote?.remoteName ?? 'origin',
    );
    _branchController = TextEditingController(
      text: remote?.branch ?? 'main',
    );
  }

  @override
  void dispose() {
    _repositoryController.dispose();
    _remoteNameController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final remote = WorkspaceGitRemote(
        repositoryUrl: _repositoryController.text,
        remoteName: _remoteNameController.text,
        branch: _branchController.text,
      );
      Navigator.pop(context, WorkspaceGitRemoteDialogResult.bind(remote));
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    } catch (error) {
      setState(() => _errorText = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExistingRemote = widget.initialRemote != null;
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(
        hasExistingRemote
            ? l10n.tr('Git 仓库设置', 'Git repository settings')
            : l10n.tr('绑定 Git 仓库', 'Connect Git repository'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.tr(
                  '这里只保存仓库地址与分支。Token、密码和 SSH 私钥不会写进 Workspace 元数据。',
                  'Only the repository address and branch are stored here. Tokens, passwords, and SSH private keys are never written to Workspace metadata.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('workspace-git-repository-url'),
                controller: _repositoryController,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Repository URL',
                  hintText: 'https://github.com/owner/repository.git',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('workspace-git-remote-name'),
                      controller: _remoteNameController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Remote',
                        hintText: 'origin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('workspace-git-branch'),
                      controller: _branchController,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        hintText: 'main',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  key: const ValueKey('workspace-git-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (hasExistingRemote)
          TextButton(
            key: const ValueKey('workspace-git-unbind'),
            onPressed: () => Navigator.pop(
              context,
              const WorkspaceGitRemoteDialogResult.unbind(),
            ),
            child: Text(l10n.tr('解绑', 'Disconnect')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('workspace-git-save'),
          onPressed: _save,
          child: Text(
            hasExistingRemote
                ? l10n.tr('保存', 'Save')
                : l10n.tr('绑定', 'Connect'),
          ),
        ),
      ],
    );
  }
}

class WorkspaceGitRemoteDialogResult {
  const WorkspaceGitRemoteDialogResult.bind(this.remote) : unbind = false;

  const WorkspaceGitRemoteDialogResult.unbind()
      : remote = null,
        unbind = true;

  final WorkspaceGitRemote? remote;
  final bool unbind;
}
