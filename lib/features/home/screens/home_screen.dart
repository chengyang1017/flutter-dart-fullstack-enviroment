import 'package:flutter/material.dart';

import '../../concept/screens/concept_mode_screen.dart';
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
                      tooltip: '绑定正式登录账号',
                      onPressed: onClaimAccount,
                      icon: const Icon(Icons.verified_user_outlined),
                    ),
                  if (onLogout != null)
                    IconButton(
                      key: const ValueKey('home-account-logout'),
                      tooltip: '退出登录',
                      onPressed: () async => onLogout!(),
                      icon: const Icon(Icons.logout_rounded),
                    ),
                ],
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                    const Text(
                      '用项目模式处理完整 Flutter 工程，用概念模式专注理解 lib/ 中的代码结构。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    _EntryCard(
                      key: const ValueKey('home-concept-mode-entry'),
                      icon: Icons.hub_outlined,
                      title: '概念模式',
                      description: '只直接操作 lib/。依赖、调用关系和状态流通过可视化工具管理。',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ConceptModeScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _EntryCard(
                      key: const ValueKey('home-project-mode-entry'),
                      icon: Icons.code,
                      title: '项目模式',
                      description: '先选择、创建或导入项目，再进入完整 Flutter Workspace。',
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
                      title: '教材模式',
                      description: '按步骤学习 Widget，用 AST 自动检查练习结果。',
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
