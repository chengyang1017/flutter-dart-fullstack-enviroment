import 'package:flutter/material.dart';

import '../models/workspace_git_pull.dart';
import '../models/workspace_git_push.dart';
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
typedef WorkspaceGitPusher = Future<WorkspaceGitPushResult> Function({
  required String commitMessage,
  required String authorName,
  required String authorEmail,
  String? secretName,
  String? username,
});

class WorkspaceGitConnectionDialog extends StatefulWidget {
  const WorkspaceGitConnectionDialog({
    super.key,
    required this.project,
    required this.loadSecrets,
    required this.checkConnection,
    required this.pullRemote,
    required this.hasLocalChanges,
    this.pushRemote,
    this.onEditRemote,
  });

  final WorkspaceProject project;
  final WorkspaceGitSecretLoader loadSecrets;
  final WorkspaceGitConnectionChecker checkConnection;
  final WorkspaceGitPuller pullRemote;
  final bool hasLocalChanges;
  final WorkspaceGitPusher? pushRemote;
  final VoidCallback? onEditRemote;

  @override
  State<WorkspaceGitConnectionDialog> createState() =>
      _WorkspaceGitConnectionDialogState();
}

class _WorkspaceGitConnectionDialogState
    extends State<WorkspaceGitConnectionDialog> {
  final TextEditingController _secretNameController = TextEditingController();
  final TextEditingController _secretValueController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _commitMessageController =
      TextEditingController();
  final TextEditingController _authorNameController = TextEditingController();
  final TextEditingController _authorEmailController = TextEditingController();

  List<WorkspaceSecretMetadata> _secrets = const [];
  WorkspaceGitRemoteCheckResult? _result;
  String? _errorText;
  bool _loadingSecrets = true;
  bool _checking = false;
  bool _pulling = false;
  bool _resetting = false;
  bool _pushing = false;
  bool _showSecret = false;
  String? _successText;
  late bool _hasLocalChanges;
  String? _lastSyncedHead;

  bool get _busy => _checking || _pulling || _resetting || _pushing;

  @override
  void initState() {
    super.initState();
    _hasLocalChanges = widget.hasLocalChanges;
    _lastSyncedHead = widget.project.gitRemote?.lastSyncedHead;
    _loadSecrets();
  }

  @override
  void dispose() {
    _secretNameController.dispose();
    _secretValueController.dispose();
    _usernameController.dispose();
    _commitMessageController.dispose();
    _authorNameController.dispose();
    _authorEmailController.dispose();
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

  Future<WorkspaceGitConnectionCheck> _checkWithInput(
    ({
      String? secretName,
      String? secretValue,
      String? username,
    }) input,
  ) async {
    final checked = await widget.checkConnection(
      secretName: input.secretName,
      secretValue: input.secretValue,
      username: input.username,
    );
    if (!mounted) return checked;

    _secretValueController.clear();
    _result = checked.result;
    _rememberSavedSecret(checked.savedSecret);
    return checked;
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
      _successText = null;
      _result = null;
    });

    try {
      final checked = await _checkWithInput(input);
      if (!mounted) return;
      setState(() {
        _checking = false;
        _result = checked.result;
        _successText = 'GitHub 状态已刷新。';
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
    if (_hasLocalChanges) {
      setState(() {
        _errorText =
            '当前 Workspace 有本地修改。普通 Pull 不会覆盖它们；如果确定不要这些修改，请使用“放弃修改并重置到 GitHub”。';
        _successText = null;
      });
      return;
    }

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

    setState(() {
      _pulling = true;
      _errorText = null;
      _successText = null;
    });

    try {
      await _checkWithInput(input);
      final pulled = await widget.pullRemote(
        secretName: input.secretName,
        username: input.username,
        allowDirtyOverwrite: false,
      );
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _hasLocalChanges = false;
        _lastSyncedHead = pulled.remoteHead;
        _successText =
            '已从 GitHub 拉取整个仓库 · ${pulled.importedFileCount} 个文件 · HEAD ${pulled.remoteHead.substring(0, 7)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pulling = false;
        _errorText = 'Git Pull 失败：$error';
      });
    }
  }

  Future<void> _resetToGitHub() async {
    if (_busy) return;

    final first = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('放弃当前所有修改并与 GitHub 一致？'),
        content: const Text(
          '当前 Workspace 中尚未推送的修改会永久丢失。GitHub 远端不会被修改。'
          '这不是普通 Pull。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('workspace-git-reset-first-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最后确认'),
        content: const Text(
          '确认后，本地 Workspace 将被 GitHub 当前分支的完整仓库内容替换。'
          '未 Push 的本地修改无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          FilledButton(
            key: const ValueKey('workspace-git-reset-final-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃修改并重置'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;

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

    setState(() {
      _resetting = true;
      _errorText = null;
      _successText = null;
    });

    try {
      await _checkWithInput(input);
      final pulled = await widget.pullRemote(
        secretName: input.secretName,
        username: input.username,
        allowDirtyOverwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _hasLocalChanges = false;
        _lastSyncedHead = pulled.remoteHead;
        _successText =
            '已放弃本地修改并重置到 GitHub · HEAD ${pulled.remoteHead.substring(0, 7)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _errorText = '重置到 GitHub 失败：$error';
      });
    }
  }

  Future<void> _push() async {
    final push = widget.pushRemote;
    if (_busy || push == null) return;

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

    final commitMessage = _commitMessageController.text.trim();
    final authorName = _authorNameController.text.trim();
    final authorEmail = _authorEmailController.text.trim();
    if (commitMessage.isEmpty || authorName.isEmpty || authorEmail.isEmpty) {
      setState(() {
        _errorText = 'Push 前请填写 Commit message、Author name 和 Author email。';
        _successText = null;
      });
      return;
    }
    if (_lastSyncedHead == null) {
      setState(() {
        _errorText = '第一次 Push 前必须先 Pull 或重置一次，以建立可信的 GitHub HEAD。';
        _successText = null;
      });
      return;
    }

    setState(() {
      _pushing = true;
      _errorText = null;
      _successText = null;
    });

    try {
      final checked = await _checkWithInput(input);
      if (!mounted) return;
      final currentHead = checked.result.remoteHead;
      if (currentHead == null || currentHead != _lastSyncedHead) {
        setState(() {
          _pushing = false;
          _errorText = 'GitHub 在你上次同步后已经变化。请先 Pull；如果不要本地修改，则使用重置到 GitHub。';
        });
        return;
      }

      final pushed = await push(
        commitMessage: commitMessage,
        authorName: authorName,
        authorEmail: authorEmail,
        secretName: input.secretName,
        username: input.username,
      );
      if (!mounted) return;
      setState(() {
        _pushing = false;
        _hasLocalChanges = false;
        _lastSyncedHead = pushed.newRemoteHead;
        _commitMessageController.clear();
        _successText = pushed.committed
            ? 'Push 成功 · HEAD ${pushed.newRemoteHead.substring(0, 7)}'
            : 'GitHub 已经与当前 Workspace 一致，没有新的提交需要 Push。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pushing = false;
        _errorText = 'Git Push 失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.project.gitRemote!;
    final repositoryLabel = remote.repositoryFullName ??
        remote.canonicalUrl ??
        remote.repositoryUrl;

    return AlertDialog(
      title: const Text('GitHub 同步'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                repositoryLabel,
                key: const ValueKey('workspace-git-connection-url'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${remote.branch}'
                '${remote.repositoryId == null ? '' : ' · Repository #${remote.repositoryId}'}',
              ),
              const SizedBox(height: 8),
              Text(
                _lastSyncedHead == null
                    ? '尚未建立同步 HEAD'
                    : '上次同步 HEAD · $_lastSyncedHead',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Git 凭据',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              const Text(
                '公开仓库可以留空。私有仓库 Token 只进入 Workspace Secret Vault，不写入仓库 URL 或 Workspace 快照。',
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
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
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
              if (widget.pushRemote != null) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Push',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('workspace-git-push-message'),
                  controller: _commitMessageController,
                  enabled: !_busy,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Commit message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('workspace-git-push-author-name'),
                        controller: _authorNameController,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'Author name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('workspace-git-push-author-email'),
                        controller: _authorEmailController,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Author email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorText!,
                  key: const ValueKey('workspace-git-connection-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_successText != null) ...[
                const SizedBox(height: 14),
                Text(
                  _successText!,
                  key: const ValueKey('workspace-git-success'),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
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
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onEditRemote != null)
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
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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
              label: Text(_checking ? '检查中…' : '检查状态'),
            ),
            OutlinedButton.icon(
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
            OutlinedButton.icon(
              key: const ValueKey('workspace-git-reset'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _busy ? null : _resetToGitHub,
              icon: _resetting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded),
              label: Text(_resetting ? '重置中…' : '放弃修改并重置'),
            ),
            if (widget.pushRemote != null)
              FilledButton.icon(
                key: const ValueKey('workspace-git-push'),
                onPressed: _busy ? null : _push,
                icon: _pushing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded),
                label: Text(_pushing ? 'Push 中…' : 'Push'),
              ),
          ],
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
                  if (result.repositoryFullName != null) ...[
                    const SizedBox(height: 4),
                    SelectableText(result.repositoryFullName!),
                  ],
                  if (result.repositoryId != null) ...[
                    const SizedBox(height: 2),
                    Text('Repository #${result.repositoryId}'),
                  ],
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
