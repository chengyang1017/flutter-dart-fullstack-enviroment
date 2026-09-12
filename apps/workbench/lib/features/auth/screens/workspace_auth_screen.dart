import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

import '../../workspace/services/http_workspace_auth_service.dart';

class WorkspaceAuthScreen extends StatefulWidget {
  const WorkspaceAuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    this.initialError,
  });

  final Future<void> Function({
    required String email,
    required String password,
  }) onLogin;

  final Future<void> Function({
    required String username,
    required String email,
    required String password,
  }) onRegister;

  final String? initialError;

  @override
  State<WorkspaceAuthScreen> createState() => _WorkspaceAuthScreenState();
}

class _WorkspaceAuthScreenState extends State<WorkspaceAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _registerMode = false;
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (_registerMode) {
        await widget.onRegister(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await widget.onLogin(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _messageFor(Object error) {
    if (error is WorkspaceAuthRequestException) {
      return switch (error.code) {
        'username_taken' =>
          context.l10n.tr('这个用户名已经被使用。', 'This username is already in use.'),
        'email_taken' => context.l10n
            .tr('这个邮箱已经注册过。', 'This email is already registered.'),
        _ when error.statusCode == 401 =>
          context.l10n.tr('邮箱或密码不正确。', 'Incorrect email or password.'),
        _ => error.message,
      };
    }
    if (error is FormatException) {
      return error.message;
    }
    return context.l10n.tr(
      '无法连接账号服务：$error',
      'Unable to connect to the account service: $error',
    );
  }

  void _setMode(bool register) {
    if (_submitting || register == _registerMode) return;
    setState(() {
      _registerMode = register;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      key: const ValueKey('workspace-auth-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppLanguageToggleButton(),
                              AppThemeToggleButton(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Icon(
                          Icons.cloud_done_outlined,
                          size: 56,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Flutter UI Playground',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _registerMode
                              ? l10n.tr(
                                  '创建账号后，项目会保存在你的云端命名空间。',
                                  'After creating an account, projects are stored in your cloud namespace.',
                                )
                              : l10n.tr(
                                  '登录后继续访问你名下的云端项目。',
                                  'Sign in to continue accessing your cloud projects.',
                                ),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        SegmentedButton<bool>(
                          segments: <ButtonSegment<bool>>[
                            ButtonSegment<bool>(
                              value: false,
                              label: Text(l10n.tr('登录', 'Sign in')),
                              icon: const Icon(Icons.login_rounded),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text(l10n.tr('注册', 'Register')),
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                            ),
                          ],
                          selected: <bool>{_registerMode},
                          onSelectionChanged: _submitting
                              ? null
                              : (selection) => _setMode(selection.first),
                        ),
                        const SizedBox(height: 22),
                        if (_registerMode) ...[
                          TextFormField(
                            key: const ValueKey('workspace-auth-username'),
                            controller: _usernameController,
                            enabled: !_submitting,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[
                              AutofillHints.username
                            ],
                            decoration: InputDecoration(
                              labelText: l10n.tr('用户名', 'Username'),
                              hintText: l10n.tr('例如 alice', 'For example, alice'),
                              border: const OutlineInputBorder(),
                              prefixIcon:
                                  const Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (value) {
                              if (!_registerMode) return null;
                              final username = value?.trim() ?? '';
                              if (username.isEmpty) {
                                return l10n.tr('请输入用户名', 'Enter a username');
                              }
                              if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$')
                                  .hasMatch(username)) {
                                return l10n.tr(
                                  '只能使用字母、数字和连字符，最多 39 个字符',
                                  'Use only letters, numbers, and hyphens, up to 39 characters',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          key: const ValueKey('workspace-auth-email'),
                          controller: _emailController,
                          enabled: !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: l10n.tr('邮箱', 'Email'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) {
                              return l10n.tr('请输入邮箱', 'Enter your email');
                            }
                            if (!email.contains('@')) {
                              return l10n.tr('请输入有效邮箱', 'Enter a valid email');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const ValueKey('workspace-auth-password'),
                          controller: _passwordController,
                          enabled: !_submitting,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: _registerMode
                              ? const <String>[AutofillHints.newPassword]
                              : const <String>[AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: l10n.tr('密码', 'Password'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? l10n.tr('显示密码', 'Show password')
                                  : l10n.tr('隐藏密码', 'Hide password'),
                              onPressed: _submitting
                                  ? null
                                  : () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.isEmpty) {
                              return l10n.tr('请输入密码', 'Enter your password');
                            }
                            if (_registerMode && password.length < 8) {
                              return l10n.tr(
                                '密码至少需要 8 个字符',
                                'Password must be at least 8 characters',
                              );
                            }
                            return null;
                          },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            key: const ValueKey('workspace-auth-error'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(color: scheme.onErrorContainer),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const ValueKey('workspace-auth-submit'),
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _registerMode
                                      ? Icons.person_add_alt_1_rounded
                                      : Icons.login_rounded,
                                ),
                          label: Text(
                            _submitting
                                ? l10n.tr('处理中...', 'Processing...')
                                : _registerMode
                                    ? l10n.tr('创建账号', 'Create account')
                                    : l10n.tr('登录', 'Sign in'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.tr(
                            '你的项目由登录账号隔离保存。浏览器只保留当前账号的本地缓存。',
                            'Projects are isolated by account. The browser keeps only the local cache for the current account.',
                          ),
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
