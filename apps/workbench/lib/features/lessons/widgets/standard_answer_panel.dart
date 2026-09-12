import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controller/lesson_controller.dart';
import '../data/author_answer_repository.dart';
import '../models/code_reference.dart';
import 'standard_answer_code_view.dart';

class StandardAnswerPanel extends StatefulWidget {
  const StandardAnswerPanel({
    super.key,
    required this.controller,
    required this.repository,
    required this.onClose,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.navigationTarget,
  });

  final LessonController controller;
  final AuthorAnswerRepository repository;
  final VoidCallback onClose;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;
  final CodeReference? navigationTarget;

  @override
  State<StandardAnswerPanel> createState() => _StandardAnswerPanelState();
}

class _StandardAnswerPanelState extends State<StandardAnswerPanel> {
  late String _stepId;
  late String selectedFile;
  late Future<AuthorAnswer> _answerFuture;
  CodeReference? _navigationTarget;

  @override
  void initState() {
    super.initState();
    _loadCurrentStep(target: widget.navigationTarget);
  }

  @override
  void didUpdateWidget(covariant StandardAnswerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentStep =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];
    final targetChanged = !_sameTarget(
      oldWidget.navigationTarget,
      widget.navigationTarget,
    );
    if (currentStep.id != _stepId || targetChanged) {
      _loadCurrentStep(target: widget.navigationTarget);
    }
  }

  bool _sameTarget(CodeReference? first, CodeReference? second) {
    if (identical(first, second)) return true;
    if (first == null || second == null) return false;
    return first.fileName == second.fileName &&
        first.stepIndex == second.stepIndex &&
        first.line == second.line &&
        first.column == second.column;
  }

  void _loadCurrentStep({CodeReference? target}) {
    final step =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];
    _stepId = step.id;
    final files = _answerFiles(step);
    final targetFile = target != null &&
            target.isStandardAnswer &&
            target.stepIndex == widget.controller.currentStepIndex &&
            files.contains(target.fileName)
        ? target.fileName
        : null;
    selectedFile = targetFile ?? (files.isNotEmpty ? files.first : step.currentFile);
    _navigationTarget = targetFile == null ? null : target;
    _loadAnswer();
  }

  List<String> _answerFiles(dynamic step) {
    if (step.standardAnswerAssets.isNotEmpty) {
      return step.standardAnswerAssets.keys.toList();
    }
    return step.relatedFiles;
  }

  void _loadAnswer() {
    final step =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];
    final path = step.standardAnswerAssets[selectedFile];
    _answerFuture = path == null
        ? Future<AuthorAnswer>.value(const AuthorAnswer.notRecorded())
        : widget.repository.load(path);
  }

  void _selectFile(String file) {
    if (selectedFile == file) return;
    setState(() {
      selectedFile = file;
      _navigationTarget = null;
      _loadAnswer();
    });
  }

  Future<void> _openDefinition(CodeReference reference) async {
    if (!reference.isStandardAnswer) {
      await widget.controller.openReference(reference);
      if (mounted) widget.onClose();
      return;
    }

    if (reference.stepIndex != widget.controller.currentStepIndex) {
      await widget.controller.goTo(reference.stepIndex);
    }
    if (!mounted) return;

    final step =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];
    final files = _answerFiles(step);
    if (!files.contains(reference.fileName)) return;

    setState(() {
      _stepId = step.id;
      selectedFile = reference.fileName;
      _navigationTarget = reference;
      _loadAnswer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final step =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];
    final files = _answerFiles(step);
    final l10n = context.l10n;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const Divider(height: 1),
          if (files.isNotEmpty) _buildFileBar(files),
          if (files.isNotEmpty) const Divider(height: 1),
          Expanded(
            child: FutureBuilder<AuthorAnswer>(
              future: _answerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.tr(
                          '读取标准答案失败：\n${snapshot.error}',
                          'Failed to load the reference answer:\n${snapshot.error}',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final answer = snapshot.data;
                if (answer == null || !answer.isAvailable || answer.code == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.tr(
                          '该部分标准答案尚未由课程作者录入。',
                          'The course author has not added a reference answer for this section yet.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    Expanded(
                      child: StandardAnswerCodeView(
                        key: ValueKey(
                          '${widget.controller.currentStepIndex}-$selectedFile-${answer.code.hashCode}',
                        ),
                        lessonController: widget.controller,
                        code: answer.code!,
                        fileName: selectedFile,
                        stepIndex: widget.controller.currentStepIndex,
                        navigationTarget: _navigationTarget,
                        onOpenDefinition: _openDefinition,
                      ),
                    ),
                    _buildActions(answer.code!),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('课程作者参考答案', 'Author reference answer'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.tr(
                    'Ctrl + 点击名称：直接切换到定义所在步骤和文件。',
                    'Ctrl + click a name to jump directly to the step and file containing its definition.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: widget.isExpanded
                ? l10n.tr('还原左右布局', 'Restore split layout')
                : l10n.tr('放大标准答案', 'Expand reference answer'),
            onPressed: widget.onToggleExpanded,
            icon: Icon(
              widget.isExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.tr('关闭参考答案', 'Close reference answer'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildFileBar(List<String> files) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: files
            .map(
              (file) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(file),
                  selected: selectedFile == file,
                  onSelected: (_) => _selectFile(file),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildActions(String code) {
    final l10n = context.l10n;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
              },
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.tr('复制', 'Copy')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _confirmReplace(code),
              icon: const Icon(Icons.find_replace),
              label: Text(l10n.tr('替换当前文件', 'Replace current file')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReplace(String code) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: Text(l10n.tr('替换 $selectedFile？', 'Replace $selectedFile?')),
        content: Text(
          l10n.tr(
            '只会替换当前选中的文件，不会自动运行代码或完成步骤。',
            'Only the selected file will be replaced. This will not run the code or complete the step automatically.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: Text(l10n.tr('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: Text(l10n.tr('确认替换', 'Replace')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await widget.controller.replaceFileWithAuthorCode(selectedFile, code);
  }
}
