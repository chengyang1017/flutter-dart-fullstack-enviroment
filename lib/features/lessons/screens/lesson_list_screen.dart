import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../data/lesson_catalog.dart';
import '../data/lesson_progress_store.dart';
import '../models/lesson.dart';
import '../models/lesson_project.dart';
import 'lesson_screen.dart';

class LessonListScreen extends StatefulWidget {
  const LessonListScreen({
    super.key,
    this.store,
    this.project,
  });

  final LessonProgressStore? store;

  /// null 代表顯示最外層的大類。
  /// 有值代表顯示該大類中的教材。
  final LessonProject? project;

  @override
  State<LessonListScreen> createState() {
    return _LessonListScreenState();
  }
}

class _LessonListScreenState extends State<LessonListScreen> {
  late final LessonProgressStore _progressStore;

  @override
  void initState() {
    super.initState();

    _progressStore = widget.store ??
        LessonProgressStore(
          Hive.box<dynamic>('lesson_progress'),
        );
  }

  Future<void> _openProject(
    LessonProject project,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LessonListScreen(
          store: _progressStore,
          project: project,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _openLesson(
    Lesson lesson,
  ) async {
    if (lesson.comingSoon) {
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LessonScreen(
          lesson: lesson,
          store: _progressStore,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  int _completedStepCount(Lesson lesson) {
    final progress = _progressStore.load(lesson.id);

    final completedSteps = (progress['completedSteps'] as List?) ?? const [];

    return completedSteps.length.clamp(0, lesson.steps.length).toInt();
  }

  int _projectCompletedSteps(
    LessonProject project,
  ) {
    return project.lessons.fold(
      0,
      (total, lesson) {
        return total + _completedStepCount(lesson);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          project?.title ?? '教材模式',
        ),
      ),
      body: SafeArea(
        child:
            project == null ? _buildProjectList() : _buildLessonList(project),
      ),
    );
  }

  Widget _buildProjectList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 850 ? 2 : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: LessonCatalog.projects.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 230,
          ),
          itemBuilder: (context, index) {
            final project = LessonCatalog.projects[index];

            return _ProjectCard(
              project: project,
              completedSteps: _projectCompletedSteps(project),
              onTap: () => _openProject(project),
            );
          },
        );
      },
    );
  }

  Widget _buildLessonList(
    LessonProject project,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: project.lessons.length,
      separatorBuilder: (context, index) {
        return const SizedBox(height: 8);
      },
      itemBuilder: (context, index) {
        final lesson = project.lessons[index];
        final completed = _completedStepCount(lesson);

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: lesson.comingSoon ? null : () => _openLesson(lesson),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    child: Text('${index + 1}'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lesson.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (lesson.comingSoon)
                              const Chip(
                                label: Text('即将推出'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(lesson.description),
                        const SizedBox(height: 8),
                        Text(
                          lesson.comingSoon
                              ? '${lesson.category} · '
                                  '${lesson.difficulty} · '
                                  '${lesson.estimatedMinutes} 分钟'
                              : '${lesson.category} · '
                                  '${lesson.difficulty} · '
                                  '${lesson.estimatedMinutes} 分钟 · '
                                  '${lesson.steps.length} 步 · '
                                  '$completed/'
                                  '${lesson.steps.length} 已完成',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: lesson.tags.map(
                            (tag) {
                              return Chip(
                                label: Text(tag),
                                visualDensity: VisualDensity.compact,
                              );
                            },
                          ).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.completedSteps,
    required this.onTap,
  });

  final LessonProject project;
  final int completedSteps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final totalSteps = project.totalStepCount;

    final progress = totalSteps == 0 ? 0.0 : completedSteps / totalSteps;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      project.icon,
                      size: 30,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                project.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${project.lessons.length} 门教材 · '
                '${project.availableLessonCount} 门可学习',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
