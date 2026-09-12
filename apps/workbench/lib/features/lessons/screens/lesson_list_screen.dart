import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';

import '../data/lesson_catalog_repository.dart';
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

  /// null 代表显示最外层的大类；有值代表显示该大类中的教材。
  final LessonProject? project;

  @override
  State<LessonListScreen> createState() => _LessonListScreenState();
}

class _LessonListScreenState extends State<LessonListScreen> {
  late final LessonProgressStore _progressStore;
  late final LessonCatalogRepository _catalogRepository;
  List<LessonProject> _projects = const <LessonProject>[];
  LessonProject? _activeProject;
  String? _catalogLanguage;
  String? _catalogError;
  bool _catalogLoading = false;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _progressStore = widget.store ??
        LessonProgressStore(Hive.box<dynamic>('lesson_progress'));
    _catalogRepository = LessonCatalogRepository();
    _activeProject = widget.project;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode =
        Localizations.localeOf(context).languageCode.toLowerCase().startsWith('en')
            ? 'en'
            : 'zh';
    if (_catalogLanguage == languageCode) return;
    _catalogLanguage = languageCode;
    Future<void>.microtask(() => _loadCatalog(languageCode: languageCode));
  }

  @override
  void dispose() {
    _catalogRepository.close();
    super.dispose();
  }

  Future<void> _loadCatalog({String? languageCode}) async {
    final requestedLanguage = languageCode ?? _catalogLanguage ?? 'zh';
    final serial = ++_loadSerial;
    if (mounted) {
      setState(() {
        _catalogLoading = true;
        _catalogError = null;
      });
    }

    try {
      final projects = await _catalogRepository.loadProjects(
        languageCode: requestedLanguage,
      );
      if (!mounted || serial != _loadSerial) return;

      LessonProject? activeProject;
      final projectId = widget.project?.id;
      if (projectId != null) {
        for (final project in projects) {
          if (project.id == projectId) {
            activeProject = project;
            break;
          }
        }
      }

      setState(() {
        _projects = projects;
        if (widget.project != null) {
          _activeProject = activeProject ?? widget.project;
        }
        _catalogLoading = false;
      });
    } catch (error) {
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _catalogError = error.toString();
        _catalogLoading = false;
      });
    }
  }

  Future<void> _openProject(LessonProject project) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LessonListScreen(
          store: _progressStore,
          project: project,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openLesson(Lesson lesson) async {
    if (lesson.comingSoon) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LessonScreen(
          lesson: lesson,
          store: _progressStore,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  int _completedStepCount(Lesson lesson) {
    final progress = _progressStore.load(lesson.id);
    final completedSteps = (progress['completedSteps'] as List?) ?? const [];
    return completedSteps.length.clamp(0, lesson.steps.length).toInt();
  }

  int _projectCompletedSteps(LessonProject project) => project.lessons.fold(
        0,
        (total, lesson) => total + _completedStepCount(lesson),
      );

  @override
  Widget build(BuildContext context) {
    final project =
        widget.project == null ? null : (_activeProject ?? widget.project);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(project?.title ?? l10n.tr('教材模式', 'Lesson mode')),
        actions: [
          IconButton(
            tooltip: l10n.tr('刷新课程', 'Refresh lessons'),
            onPressed: _catalogLoading
                ? null
                : () => _loadCatalog(languageCode: _catalogLanguage),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const AppLanguageToggleButton(),
          const AppThemeToggleButton(),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_catalogLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: project == null
                  ? _buildProjectContent()
                  : _buildLessonList(project),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectContent() {
    final l10n = context.l10n;
    if (_catalogError != null && _projects.isEmpty) {
      return _CatalogState(
        icon: Icons.cloud_off_rounded,
        title: l10n.tr('无法加载课程', 'Unable to load lessons'),
        message: _catalogError!,
        actionLabel: l10n.tr('重试', 'Retry'),
        onRetry: () => _loadCatalog(languageCode: _catalogLanguage),
      );
    }
    if (!_catalogLoading && _projects.isEmpty) {
      return _CatalogState(
        icon: Icons.school_outlined,
        title: l10n.tr('还没有已发布课程', 'No published lessons yet'),
        message: l10n.tr(
          '课程现在由管理员后台统一管理。请先在后台创建并发布课程。',
          'Lessons are managed by the admin console. Create and publish a course there first.',
        ),
        actionLabel: l10n.tr('刷新', 'Refresh'),
        onRetry: () => _loadCatalog(languageCode: _catalogLanguage),
      );
    }
    return _buildProjectList();
  }

  Widget _buildProjectList() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 850 ? 2 : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _projects.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 230,
          ),
          itemBuilder: (context, index) {
            final project = _projects[index];
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

  Widget _buildLessonList(LessonProject project) {
    final l10n = context.l10n;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: project.lessons.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
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
                  CircleAvatar(child: Text('${index + 1}')),
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
                              Chip(
                                label: Text(l10n.tr('即将推出', 'Coming soon')),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(lesson.description),
                        const SizedBox(height: 8),
                        Text(
                          lesson.comingSoon
                              ? '${lesson.category} · ${lesson.difficulty} · ${lesson.estimatedMinutes} ${l10n.tr('分钟', 'min')}'
                              : '${lesson.category} · ${lesson.difficulty} · ${lesson.estimatedMinutes} ${l10n.tr('分钟', 'min')} · ${lesson.steps.length} ${l10n.tr('步', 'steps')} · $completed/${lesson.steps.length} ${l10n.tr('已完成', 'completed')}',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: lesson.tags
                              .map(
                                (tag) => Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CatalogState extends StatelessWidget {
  const _CatalogState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54),
              const SizedBox(height: 18),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
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
    final l10n = context.l10n;
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
                  const Icon(Icons.arrow_forward),
                ],
              ),
              const SizedBox(height: 18),
              Text(project.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '${project.lessons.length} ${l10n.tr('门教材', 'lessons')} · ${project.availableLessonCount} ${l10n.tr('门可学习', 'available')}',
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
      ),
    );
  }
}
