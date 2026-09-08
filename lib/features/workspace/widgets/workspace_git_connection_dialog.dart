import 'package:flutter/material.dart';

import '../models/workspace_git_pull.dart';
import '../models/workspace_git_remote_check.dart';
import '../models/workspace_project.dart';
import '../models/workspace_secret.dart';
import '../services/workspace_git_connection_coordinator.dart';

typedef WorkspaceGitSecretLoader = Future<List<WorkspaceSecretMetadata>>
    Function();
typedef WorkspaceGitConnectionChecker = Future<WorkspaceGitConnectionCheck>
    Function({
  String? secretName,
  String? secretValue,
  String? username,
});
typedef WorkspaceGitPuller = Future<WorkspaceGitPullResult> Function({
  String? secretName,
  String? username,
  bool allowDirtyOverwrite,
});

class WorkspaceGitConnectionDialog extends StatefulWidget {
  const WorkspaceGitConnectionDialog({
    super.key,
    required this.project,
    required this.loadSecrets,
    required this.checkConnection,
    required this.pullRemote,
    required this.hasLocalChanges,
    required this.onEditRemote,
  });

  final WorkspaceProject project;
  final WorkspaceGitSecretLoader loadSecrets;
  final WorkspaceGitConnectionChecker checkConnection;
  final WorkspaceGitPuller pullRemote;
  final bool hasLocalChanges;
  final VoidCallback onEditRemote;

  @override
  State<WorkspaceGitConnectionDialog> createState() =>
      _WorkspaceGitConnectionDialogState();
}

class _WorkspaceGitConnectionDialogState
    extends State<WorkspaceGitConnectionDialog> {
  final TextEditingController _secretNameController = TextEditingController();
  final TextEditingController _secretValueController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  List<WorkspaceSecretMetadata> _secrets = const [];
  WorkspaceGitRemoteCheckResult? _result;
  String? _errorText;
  bool _loadingSecrets = true;
  bool _checking = false;
  bool _pulling = false;
  bool _showSecret = false;

  bool get _busy => _checking || _pulling;

  @override
  void initState() {
    super.initState();
    _loadSecrets();
  }

  @override
  void dispose() {
    _secretNameController.dispose();
    _secretValueController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadSecrets() async {
    try {
      final secrets = await widget.loadSecrets();
      if (!mounted) return;
      setState(() {
        _secrets = secrets;
        _loadingSecrets = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSecrets = false;
        _errorText = '读取 Git 凭据失败：$error';
      });
    }
  }

  ({String? secretName, String? secretValue, String? username})
      _credentialInput() {
    final secretNameText = _secretNameController.text.trim();
    final secretValueText = _secretValueController.text;
    if (secretValueText.isNotEmpty && secretNameText.isEmpty) {
      throw const FormatException('输入 Token 时必须同时填写 Secret name。');
    }
    final usernameText = _usernameController.text.trim();
    return (
      secretName: secretNameText.isEmpty ? null : secretNameText,
      secretValue: secretValueText.isEmpty ? null : secretValueText,
      username: usernameText.isEmpty ? null : usernameText,
    );
  }

  void _rememberSavedSecret(WorkspaceSecretMetadata? saved) {
    if (saved == null || _secrets.any((item) => item.name == saved.name))
      return;
    _secrets = [..._secrets, saved]..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _check() async {
    if (_busy) return;

    late final ({
      String? secretName,
      String? secretValue,
      String? username
    }) input;
    try {
      input = _credentialInput();
    } on FormatException catch (error) {
      setState(() {
        _errorText = error.message;
        _result = null;
      });
      return;
    }

    setState(() {
      _checking = true;
      _errorText = null;
      _result = null;
    });

    try {
      final checked = await widget.checkConnection(
        secretName: input.secretName,
        secretValue: input.secretValue,
        username: input.username,
      );
      if (!mounted) return;

      _secretValueController.clear();
      setState(() {
        _checking = false;
        _result = checked.result;
        _rememberSavedSecret(checked.savedSecret);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _errorText = 'Git 连接检查失败：$error';
      });
    }
  }

  Future<void> _pull() async {
    if (_busy) return;

    late final ({
      String? secretName,
      String? secretValue,
      String? username
    }) input;
    try {
      input = _credentialInput();
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
      return;
    }

    var allowDirtyOverwrite = false;
    if (widget.hasLocalChanges) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('用 Git 远端覆盖本地修改？'),
          content: const Text(
            '当前 Workspace 有尚未提交的本地修改。Pull 会用远端分支内容替换当前 Workspace。'
            '如果这些修改还需要，请先导出或之后使用 Commit + Push。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('workspace-git-pull-confirm-overwrite'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('覆盖并 Pull'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      allowDirtyOverwrite = true;
    }

    setState(() {
      _pulling = true;
      _errorText = null;
    });

    try {
      // A newly typed token has not reached the vault yet. Reuse the check
      // path to save it securely before asking the pull endpoint to resolve it.
      if (input.secretValue != null) {
        final checked = await widget.checkConnection(
          secretName: input.secretName,
          secretValue: input.secretValue,
          username: input.username,
        );
        if (!mounted) return;
        _secretValueController.clear();
        _result = checked.result;
        _rememberSavedSecret(checked.savedSecret);
      }

      final pulled = await widget.pullRemote(
        secretName: input.secretName,
        username: input.username,
        allowDirtyOverwrite: allowDirtyOverwrite,
      );
      if (!mounted) return;
      Navigator.pop(context, pulled);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _errorText = 'Git Pull 失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.project.gitRemote!;

    return AlertDialog(
      title: const Text('Git 连接'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                remote.repositoryUrl,
                key: const ValueKey('workspace-git-connection-url'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('${remote.remoteName} · ${remote.branch}'),
              const SizedBox(height: 16),
              Text(
                'Git 凭据',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                'Token 只会发送到 Workspace Secret Vault，不会写入仓库 URL、Workspace 元数据或浏览器快照。公开仓库可以留空。',
              ),
              const SizedBox(height: 12),
              if (_loadingSecrets)
                const LinearProgressIndicator(
                  key: ValueKey('workspace-git-secrets-loading'),
                )
              else if (_secrets.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _secrets
                      .map(
                        (secret) => ActionChip(
                          key: ValueKey('workspace-git-secret-${secret.name}'),
                          label: Text(secret.name),
                          onPressed: _busy
                              ? null
                              : () {
                                  _secretNameController.text = secret.name;
                                  setState(() => _errorText = null);
                                },
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const ValueKey('workspace-git-secret-name'),
                controller: _secretNameController,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Secret name（可选）',
                  hintText: '例如 GITHUB_TOKEN',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-git-secret-value'),
                controller: _secretValueController,
                enabled: !_busy,
                obscureText: !_showSecret,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Token / password（仅保存新值时填写）',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _showSecret ? '隐藏凭据' : '显示凭据',
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showSecret = !_showSecret),
                    icon: Icon(
                      _showSecret ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-git-username'),
                controller: _usernameController,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Username（通常可留空）',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorText!,
                  key: const ValueKey('workspace-git-connection-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 14),
                _GitCheckResultCard(result: _result!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('workspace-git-edit-remote'),
          onPressed: _busy ? null : widget.onEditRemote,
          icon: const Icon(Icons.settings_outlined),
          label: const Text('仓库设置'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('workspace-git-check'),
          onPressed: _busy ? null : _check,
          icon: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check_outlined),
          label: Text(_checking ? '检查中…' : '检查连接'),
        ),
        FilledButton.icon(
          key: const ValueKey('workspace-git-pull'),
          onPressed: _busy ? null : _pull,
          icon: _pulling
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(_pulling ? 'Pull 中…' : 'Pull'),
        ),
      ],
    );
  }
}

class _GitCheckResultCard extends StatelessWidget {
  const _GitCheckResultCard({required this.result});

  final WorkspaceGitRemoteCheckResult result;

  @override
  Widget build(BuildContext context) {
    final branchFound = result.branchFound;
    final message = branchFound
        ? '仓库可访问，分支 ${result.branch} 存在。'
        : '仓库可访问，但找不到分支 ${result.branch}。';
    final head = result.remoteHead;

    return Card(
      key: const ValueKey('workspace-git-connection-result'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                branchFound ? Icons.check_circle_outline : Icons.warning_amber),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  if (head != null) ...[
                    const SizedBox(height: 4),
                    SelectableText('HEAD: $head'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
