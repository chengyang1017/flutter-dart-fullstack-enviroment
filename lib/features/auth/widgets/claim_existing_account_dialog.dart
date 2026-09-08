import 'package:flutter/material.dart';

import '../../workspace/services/http_workspace_auth_service.dart';

typedef ClaimExistingAccountCallback = Future<void> Function({
  required String email,
  required String password,
});

class ClaimExistingAccountDialog extends StatefulWidget {
  const ClaimExistingAccountDialog({
    super.key,
    required this.username,
    required this.onClaim,
  });

  final String username;
  final ClaimExistingAccountCallback onClaim;

  @override
  State<ClaimExistingAccountDialog> createState() =>
      _ClaimExistingAccountDialogState();
}

class _ClaimExistingAccountDialogState
    extends State<ClaimExistingAccountDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (email.isEmpty) {
      setState(() => _error = '请输入邮箱。');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onClaim(email: email, password: password);
      if (mounted) Navigator.of(context).pop(true);
    } on WorkspaceAuthRequestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('claim-existing-account-dialog'),
      title: const Text('绑定正式登录账号'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '当前开发身份：${widget.username}\n绑定后会保留原来的 userId、项目和云端数据，只新增邮箱密码登录。',
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('claim-existing-email'),
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: '邮箱',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('claim-existing-password'),
                controller: _passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: '新密码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('claim-existing-password-confirm'),
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认密码',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey('claim-existing-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('claim-existing-submit'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user_outlined),
          label: Text(_submitting ? '绑定中...' : '绑定账号'),
        ),
      ],
    );
  }
}
