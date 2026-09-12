import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

import '../../lessons/screens/lesson_list_screen.dart';
import '../../project_mode/screens/project_mode_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.username,
    this.onClaimAccount,
    this.onLogout,
  });

  final String? username;
  final VoidCallback? onClaimAccount;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: username == null && onLogout == null && onClaimAccount == null
            ? null
            : AppBar(
                title: username == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_circle_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            username!,
                            key: const ValueKey('home-account-username'),
                          ),
                        ],
                      ),
                actions: [
                  if (onClaimAccount != null)
                    IconButton(
                      key: const ValueKey('home-account-claim'),
                      tooltip: context.l10n.tr(
                        '绑定正式登录账号',
                        'Link a permanent login account',
                      ),
                      onPressed: onClaimAccount,
                      icon: const Icon(Icons.verified_user_outlined),
                    ),
                  if (onLogout != null)
                    IconButton(
                      key: const ValueKey('home-account-logout'),
                      tooltip: context.l10n.tr('退出登录', 'Log out'),
                      onPressed: () async => onLogout!(),
                      icon: const Icon(Icons.logout_rounded),
                    ),
                ],
              ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                          const SizedBox(height: 8),
                          Icon(
                            Icons.widgets_outlined,
                            size: 72,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Flutter UI Playground',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.tr(
                              '打开一个真实 Flutter 项目，然后在项目视角和概念视角之间自由切换。',
                              'Open a real Flutter project, then switch freely between Project View and Concept View.',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 40),
                          _EntryCard(
                            key: const ValueKey('home-start-project-entry'),
                            icon: Icons.rocket_launch_outlined,
                            title: context.l10n.tr('开始项目', 'Start a project'),
                            description: context.l10n.tr(
                              '创建、打开或导入 Flutter 项目。进入 Workspace 后再切换项目视角或概念视角。',
                              'Create, open, or import a Flutter project. Once inside the Workspace, switch between Project View and Concept View.',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const ProjectModeScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _EntryCard(
                            key: const ValueKey('home-lesson-mode-entry'),
                            icon: Icons.school_outlined,
                            title: context.l10n.tr('教材模式', 'Lesson mode'),
                            description: context.l10n.tr(
                              '按步骤学习 Widget，用 AST 自动检查练习结果。',
                              'Learn Widgets step by step and automatically check exercises with the AST.',
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const LessonListScreen(),
                              ),
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

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(icon, size: 40),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(description),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
}
