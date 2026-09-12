import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../controller/lesson_controller.dart';
import '../data/author_answer_repository.dart';
import '../data/lesson_progress_store.dart';
import '../models/code_reference.dart';
import '../models/lesson.dart';
import '../widgets/lesson_action_bar.dart';
import '../widgets/lesson_code_panel.dart';
import '../widgets/lesson_preview_panel.dart';
import '../widgets/lesson_result_panel.dart';
import '../widgets/lesson_task_panel.dart';
import '../widgets/standard_answer_dialog.dart';
import '../widgets/standard_answer_panel.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.lesson,
    required this.store,
  });

  final Lesson lesson;
  final LessonProgressStore store;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late final LessonController controller;
  late final AuthorAnswerRepository answerRepository;

  bool _showAnswerPanel = false;
  bool _isAnswerExpanded = false;
  CodeReference? _standardAnswerTarget;

  @override
  void initState() {
    super.initState();
    answerRepository = AuthorAnswerRepository();
    controller = LessonController(
      lesson: widget.lesson,
      store: widget.store,
      answerRepository: answerRepository,
    )..addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _closeAnswerPanel() {
    setState(() {
      _showAnswerPanel = false;
      _isAnswerExpanded = false;
      _standardAnswerTarget = null;
    });
  }

  void _toggleAnswerExpanded() {
    setState(() => _isAnswerExpanded = !_isAnswerExpanded);
  }

  Future<void> _openStandardAnswerReference(CodeReference reference) async {
    if (!reference.isStandardAnswer) {
      await controller.openReference(reference);
      return;
    }

    if (reference.stepIndex != controller.currentStepIndex) {
      await controller.goTo(reference.stepIndex);
    }
    if (!mounted) return;

    final width = MediaQuery.sizeOf(context).width;
    if (width < 1100) {
      await showStandardAnswerDialog(
        context,
        controller,
        answerRepository,
        initialTarget: reference,
      );
      return;
    }

    setState(() {
      _showAnswerPanel = true;
      _standardAnswerTarget = reference;
    });
  }

  Future<void> _handleAnswer() async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 1100) {
      await showStandardAnswerDialog(context, controller, answerRepository);
      return;
    }

    if (_showAnswerPanel) {
      _closeAnswerPanel();
      return;
    }

    await controller.markAnswerViewed();
    if (!mounted) return;

    setState(() {
      _showAnswerPanel = true;
      _isAnswerExpanded = false;
      _standardAnswerTarget = null;
    });
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (controller.isComplete) {
              return _LessonCompletionView(controller: controller);
            }

            final isPortrait =
                MediaQuery.orientationOf(context) == Orientation.portrait;

            if (constraints.maxWidth < 600) {
              return DefaultTabController(
                length: 4,
                child: _CompactLesson(
                  controller: controller,
                  onOpenStandardAnswerReference: _openStandardAnswerReference,
                ),
              );
            }

            if (isPortrait) {
              return _TabletPortraitLesson(
                controller: controller,
                answerRepository: answerRepository,
                showAnswer: _showAnswerPanel,
                isAnswerExpanded: _isAnswerExpanded,
                standardAnswerTarget: _standardAnswerTarget,
                onCloseAnswer: _closeAnswerPanel,
                onToggleAnswerExpanded: _toggleAnswerExpanded,
                onOpenStandardAnswerReference: _openStandardAnswerReference,
              );
            }

            if (constraints.maxWidth < 900) {
              return DefaultTabController(
                length: 4,
                child: _CompactLesson(
                  controller: controller,
                  onOpenStandardAnswerReference: _openStandardAnswerReference,
                ),
              );
            }

            return _WideLesson(
              controller: controller,
              answerRepository: answerRepository,
              showAnswer: _showAnswerPanel,
              isAnswerExpanded: _isAnswerExpanded,
              standardAnswerTarget: _standardAnswerTarget,
              onCloseAnswer: _closeAnswerPanel,
              onToggleAnswerExpanded: _toggleAnswerExpanded,
              onOpenStandardAnswerReference: _openStandardAnswerReference,
            );
          },
        ),
      ),
      bottomNavigationBar: controller.isComplete || keyboardVisible
          ? null
          : LessonActionBar(
              controller: controller,
              onAnswer: _handleAnswer,
            ),
    );
  }
}

class _LessonCompletionView extends StatelessWidget {
  const _LessonCompletionView({required this.controller});

  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.emoji_events,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.tr(
                '课程完成：${controller.lesson.title}',
                'Lesson complete: ${controller.lesson.title}',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  l10n.tr(
                    'TextField / 发布按钮\n→ _publishPost()\n→ PostService.createPost()\n→ Firebase Auth、Storage、Firestore',
                    'TextField / Publish button\n→ _publishPost()\n→ PostService.createPost()\n→ Firebase Auth, Storage, Firestore',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    height: 1.7,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l10n.tr('返回课程列表', 'Back to lessons')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.restartLesson,
                    icon: const Icon(Icons.replay),
                    label: Text(l10n.tr('重新学习', 'Restart lesson')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonHeader extends StatelessWidget {
  const _LessonHeader({required this.controller});

  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.tr('返回', 'Back'),
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.lesson.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  l10n.tr(
                    '步骤 ${controller.currentStepIndex + 1}/${controller.lesson.steps.length} · 已完成 ${controller.completedSteps.length}',
                    'Step ${controller.currentStepIndex + 1}/${controller.lesson.steps.length} · ${controller.completedSteps.length} completed',
                  ),
                ),
              ],
            ),
          ),
          const AppLanguageToggleButton(compact: true),
          const AppThemeToggleButton(compact: true),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: LinearProgressIndicator(
              value: controller.completedSteps.length /
                  controller.lesson.steps.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactLesson extends StatelessWidget {
  const _CompactLesson({
    required this.controller,
    required this.onOpenStandardAnswerReference,
  });

  final LessonController controller;
  final Future<void> Function(CodeReference reference)
      onOpenStandardAnswerReference;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('compact-lesson-layout'),
      children: [
        _LessonHeader(controller: controller),
        TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: l10n.tr('任务', 'Task')),
            Tab(text: l10n.tr('代码', 'Code')),
            Tab(text: l10n.tr('预览', 'Preview')),
            Tab(text: l10n.tr('结果', 'Result')),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              LessonTaskPanel(controller: controller),
              LessonCodePanel(
                controller: controller,
                onOpenStandardAnswerReference: onOpenStandardAnswerReference,
                onRun: () async {
                  final succeeded = await controller.runCurrentUi();
                  if (!context.mounted) return;
                  DefaultTabController.of(context).animateTo(succeeded ? 2 : 3);
                },
              ),
              LessonPreviewPanel(
                currentStep:
                    controller.lesson.steps[controller.currentStepIndex],
                playgroundController: controller.playground,
              ),
              LessonResultPanel(controller: controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabletPortraitLesson extends StatefulWidget {
  const _TabletPortraitLesson({
    required this.controller,
    required this.answerRepository,
    required this.showAnswer,
    required this.isAnswerExpanded,
    required this.standardAnswerTarget,
    required this.onCloseAnswer,
    required this.onToggleAnswerExpanded,
    required this.onOpenStandardAnswerReference,
  });

  final LessonController controller;
  final AuthorAnswerRepository answerRepository;
  final bool showAnswer;
  final bool isAnswerExpanded;
  final CodeReference? standardAnswerTarget;
  final VoidCallback onCloseAnswer;
  final VoidCallback onToggleAnswerExpanded;
  final Future<void> Function(CodeReference reference)
      onOpenStandardAnswerReference;

  @override
  State<_TabletPortraitLesson> createState() =>
      _TabletPortraitLessonState();
}

class _TabletPortraitLessonState extends State<_TabletPortraitLesson> {
  double _codeFraction = 0.58;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('tablet-portrait-lesson-layout'),
      children: [
        _LessonHeader(controller: widget.controller),
        Expanded(
          child: widget.showAnswer
              ? StandardAnswerPanel(
                  controller: widget.controller,
                  repository: widget.answerRepository,
                  navigationTarget: widget.standardAnswerTarget,
                  isExpanded: true,
                  onToggleExpanded: widget.onToggleAnswerExpanded,
                  onClose: widget.onCloseAnswer,
                )
              : _buildNormalLayout(),
        ),
      ],
    );
  }

  Widget _buildNormalLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerHeight = 8.0;
        final totalHeight = constraints.maxHeight;
        final availableHeight = totalHeight - dividerHeight;
        final minimumCodeHeight = availableHeight * 0.42;
        final minimumLowerHeight = availableHeight * 0.30;
        final maximumCodeHeight =
            totalHeight - minimumLowerHeight - dividerHeight;
        final requestedCodeHeight = totalHeight * _codeFraction;
        final codeHeight = requestedCodeHeight
            .clamp(minimumCodeHeight, maximumCodeHeight)
            .toDouble();
        final lowerHeight = totalHeight - codeHeight - dividerHeight;

        return Column(
          children: [
            SizedBox(
              height: codeHeight,
              child: LessonCodePanel(
                controller: widget.controller,
                onOpenStandardAnswerReference:
                    widget.onOpenStandardAnswerReference,
                onRun: () async {
                  await widget.controller.runCurrentUi();
                },
              ),
            ),
            _ResizableHorizontalDivider(
              height: dividerHeight,
              onDrag: (delta) {
                setState(() {
                  final nextCodeHeight = codeHeight + delta;
                  _codeFraction = (nextCodeHeight / totalHeight)
                      .clamp(
                        minimumCodeHeight / totalHeight,
                        maximumCodeHeight / totalHeight,
                      )
                      .toDouble();
                });
              },
            ),
            SizedBox(
              height: lowerHeight,
              child: _TabletLowerPanel(controller: widget.controller),
            ),
          ],
        );
      },
    );
  }
}

class _TabletLowerPanel extends StatelessWidget {
  const _TabletLowerPanel({required this.controller});

  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: TabBar(
              tabs: [
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.preview_outlined, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('预览', 'Preview')),
                    ],
                  ),
                ),
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('任务', 'Task')),
                    ],
                  ),
                ),
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.terminal, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('结果', 'Result')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                LessonPreviewPanel(
                  currentStep:
                      controller.lesson.steps[controller.currentStepIndex],
                  playgroundController: controller.playground,
                ),
                LessonTaskPanel(controller: controller),
                LessonResultPanel(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResizableHorizontalDivider extends StatelessWidget {
  const _ResizableHorizontalDivider({
    required this.height,
    required this.onDrag,
  });

  final double height;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: SizedBox(
          height: height,
          child: Center(
            child: Container(height: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

class _WideLesson extends StatefulWidget {
  const _WideLesson({
    required this.controller,
    required this.answerRepository,
    required this.showAnswer,
    required this.isAnswerExpanded,
    required this.standardAnswerTarget,
    required this.onCloseAnswer,
    required this.onToggleAnswerExpanded,
    required this.onOpenStandardAnswerReference,
  });

  final LessonController controller;
  final AuthorAnswerRepository answerRepository;
  final bool showAnswer;
  final bool isAnswerExpanded;
  final CodeReference? standardAnswerTarget;
  final VoidCallback onCloseAnswer;
  final VoidCallback onToggleAnswerExpanded;
  final Future<void> Function(CodeReference reference)
      onOpenStandardAnswerReference;

  @override
  State<_WideLesson> createState() => _WideLessonState();
}

class _WideLessonState extends State<_WideLesson> {
  double _leftFraction = 0.62;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('wide-lesson-layout'),
      children: [
        _LessonHeader(controller: widget.controller),
        Expanded(
          child: widget.showAnswer && widget.isAnswerExpanded
              ? StandardAnswerPanel(
                  controller: widget.controller,
                  repository: widget.answerRepository,
                  navigationTarget: widget.standardAnswerTarget,
                  isExpanded: true,
                  onToggleExpanded: widget.onToggleAnswerExpanded,
                  onClose: widget.onCloseAnswer,
                )
              : _buildNormalLayout(),
        ),
      ],
    );
  }

  Widget _buildNormalLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 8.0;
        const minimumLeftWidth = 500.0;
        const minimumRightWidth = 360.0;
        final totalWidth = constraints.maxWidth;
        final maximumLeftWidth = totalWidth - minimumRightWidth - dividerWidth;
        final requestedLeftWidth = totalWidth * _leftFraction;
        final leftWidth = requestedLeftWidth
            .clamp(minimumLeftWidth, maximumLeftWidth)
            .toDouble();
        final rightWidth = totalWidth - leftWidth - dividerWidth;

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: LessonCodePanel(
                controller: widget.controller,
                onOpenStandardAnswerReference:
                    widget.onOpenStandardAnswerReference,
                onRun: () async {
                  await widget.controller.runCurrentUi();
                },
              ),
            ),
            _ResizableDivider(
              width: dividerWidth,
              onDrag: (delta) {
                setState(() {
                  final nextLeftWidth = leftWidth + delta;
                  _leftFraction = (nextLeftWidth / totalWidth)
                      .clamp(
                        minimumLeftWidth / totalWidth,
                        maximumLeftWidth / totalWidth,
                      )
                      .toDouble();
                });
              },
            ),
            SizedBox(
              width: rightWidth,
              child: widget.showAnswer
                  ? StandardAnswerPanel(
                      controller: widget.controller,
                      repository: widget.answerRepository,
                      navigationTarget: widget.standardAnswerTarget,
                      isExpanded: false,
                      onToggleExpanded: widget.onToggleAnswerExpanded,
                      onClose: widget.onCloseAnswer,
                    )
                  : _LessonRightPanel(controller: widget.controller),
            ),
          ],
        );
      },
    );
  }
}

class _ResizableDivider extends StatelessWidget {
  const _ResizableDivider({required this.width, required this.onDrag});

  final double width;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(width: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

class _LessonRightPanel extends StatelessWidget {
  const _LessonRightPanel({required this.controller});

  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: TabBar(
              tabs: [
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.preview_outlined, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('预览', 'Preview')),
                    ],
                  ),
                ),
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('任务', 'Task')),
                    ],
                  ),
                ),
                Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.terminal, size: 19),
                      const SizedBox(width: 6),
                      Text(l10n.tr('结果', 'Result')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              children: [
                LessonPreviewPanel(
                  currentStep:
                      controller.lesson.steps[controller.currentStepIndex],
                  playgroundController: controller.playground,
                ),
                LessonTaskPanel(controller: controller),
                LessonResultPanel(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
