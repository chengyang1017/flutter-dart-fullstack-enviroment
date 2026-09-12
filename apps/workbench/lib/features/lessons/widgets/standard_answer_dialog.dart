import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controller/lesson_controller.dart';
import '../data/author_answer_repository.dart';
import '../models/code_reference.dart';
import 'standard_answer_code_view.dart';

Future<void> showStandardAnswerDialog(
  BuildContext context,
  LessonController controller,
  AuthorAnswerRepository repository, {
  CodeReference? initialTarget,
}) async {
  await controller.markAnswerViewed();

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) => _StandardAnswerDialog(
      controller: controller,
      repository: repository,
      initialTarget: initialTarget,
    ),
  );
}

class _StandardAnswerDialog extends StatefulWidget {
  const _StandardAnswerDialog({
    required this.controller,
    required this.repository,
    this.initialTarget,
  });

  final LessonController controller;
  final AuthorAnswerRepository repository;
  final CodeReference? initialTarget;

  @override
  State<_StandardAnswerDialog> createState() => _StandardAnswerDialogState();
}

class _StandardAnswerDialogState extends State<_StandardAnswerDialog> {
  late String _stepId;
  late String selectedFile;
  late Future<AuthorAnswer> _answerFuture;
  CodeReference? _navigationTarget;

  @override
  void initState() {
    super.initState();
    _loadCurrentStep(target: widget.initialTarget);
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
      if (mounted) Navigator.of(context).pop();
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

    return AlertDialog(
      title: Text(l10n.tr('课程作者参考答案', 'Author reference answer')),
      content: SizedBox(
        width: 880,
        height: 660,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.tr(
                '当前步骤：${widget.controller.currentStepIndex + 1}　Ctrl + 点击会直接跳到定义所在步骤。',
                'Current step: ${widget.controller.currentStepIndex + 1}   Ctrl + click jumps directly to the step containing the definition.',
              ),
            ),
            const SizedBox(height: 12),
            if (files.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
              ),
            if (files.isNotEmpty) const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<AuthorAnswer>(
                future: _answerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        l10n.tr(
                          '读取标准答案失败：\n${snapshot.error}',
                          'Failed to load the reference answer:\n${snapshot.error}',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final answer = snapshot.data;
                  if (answer == null ||
                      !answer.isAvailable ||
                      answer.code == null) {
                    return Center(
                      child: Text(
                        l10n.tr(
                          '该部分标准答案尚未由课程作者录入。',
                          'The course author has not added a reference answer for this section yet.',
                        ),
                      ),
                    );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FutureBuilder<AuthorAnswer>(
          future: _answerFuture,
          builder: (context, snapshot) {
            final answer = snapshot.data;
            final enabled = answer?.isAvailable == true && answer?.code != null;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: enabled
                      ? () async {
                          await Clipboard.setData(ClipboardData(text: answer!.code!));
                        }
                      : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: Text(l10n.tr('复制', 'Copy')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: enabled
                      ? () => _confirmReplace(context, answer!.code!)
                      : null,
                  child: Text(l10n.tr('替换当前文件', 'Replace current file')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.tr('关闭', 'Close')),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmReplace(BuildContext context, String code) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) => AlertDialog(
        title: Text(l10n.tr('替换 $selectedFile？', 'Replace $selectedFile?')),
        content: Text(
          l10n.tr(
            '只会替换当前选中的文件，不会运行代码或完成步骤。',
            'Only the selected file will be replaced. This will not run the code or complete the step.',
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
    if (context.mounted) Navigator.pop(context);
  }
}
