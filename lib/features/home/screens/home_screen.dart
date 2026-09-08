import 'package:flutter/material.dart';

import '../../concept/screens/concept_mode_screen.dart';
import '../../lessons/screens/lesson_list_screen.dart';
import '../../playground/screens/playground_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      description: '完整 Flutter Workspace：项目结构、运行、导入、平台文件和真实工程操作。',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const PlaygroundScreen(),
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
