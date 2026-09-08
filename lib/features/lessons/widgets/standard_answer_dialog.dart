import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  if (!context.mounted) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (_) {
      return _StandardAnswerDialog(
        controller: controller,
        repository: repository,
        initialTarget: initialTarget,
      );
    },
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
  State<_StandardAnswerDialog> createState() {
    return _StandardAnswerDialogState();
  }
}

class _StandardAnswerDialogState extends State<_StandardAnswerDialog> {
  late String _stepId;
  late String selectedFile;
  late Future<AuthorAnswer> _answerFuture;

  CodeReference? _navigationTarget;

  @override
  void initState() {
    super.initState();

    _loadCurrentStep(
      target: widget.initialTarget,
    );
  }

  void _loadCurrentStep({
    CodeReference? target,
  }) {
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

    selectedFile =
        targetFile ?? (files.isNotEmpty ? files.first : step.currentFile);

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
        ? Future<AuthorAnswer>.value(
            const AuthorAnswer.notRecorded(),
          )
        : widget.repository.load(path);
  }

  void _selectFile(String file) {
    if (selectedFile == file) {
      return;
    }

    setState(() {
      selectedFile = file;
      _navigationTarget = null;
      _loadAnswer();
    });
  }

  Future<void> _openDefinition(
    CodeReference reference,
  ) async {
    if (!reference.isStandardAnswer) {
      await widget.controller.openReference(reference);

      if (mounted) {
        Navigator.of(context).pop();
      }

      return;
    }

    if (reference.stepIndex != widget.controller.currentStepIndex) {
      await widget.controller.goTo(
        reference.stepIndex,
      );
    }

    if (!mounted) {
      return;
    }

    final step =
        widget.controller.lesson.steps[widget.controller.currentStepIndex];

    final files = _answerFiles(step);

    if (!files.contains(reference.fileName)) {
      return;
    }

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

    return AlertDialog(
      title: const Text(
        '课程作者参考答案',
      ),
      content: SizedBox(
        width: 880,
        height: 660,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前步骤：${widget.controller.currentStepIndex + 1}'
              '　Ctrl + 点击会直接跳到定义所在步骤。',
            ),
            const SizedBox(height: 12),
            if (files.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: files.map(
                    (file) {
                      return Padding(
                        padding: const EdgeInsets.only(
                          right: 8,
                        ),
                        child: ChoiceChip(
                          label: Text(file),
                          selected: selectedFile == file,
                          onSelected: (_) {
                            _selectFile(file);
                          },
                        ),
                      );
                    },
                  ).toList(),
                ),
              ),
            if (files.isNotEmpty) const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<AuthorAnswer>(
                future: _answerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '读取标准答案失败：\n'
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final answer = snapshot.data;

                  if (answer == null ||
                      !answer.isAvailable ||
                      answer.code == null) {
                    return const Center(
                      child: Text(
                        '该部分标准答案尚未由课程作者录入。',
                      ),
                    );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: StandardAnswerCodeView(
                      key: ValueKey(
                        '${widget.controller.currentStepIndex}-'
                        '$selectedFile-'
                        '${answer.code.hashCode}',
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
                          await Clipboard.setData(
                            ClipboardData(
                              text: answer!.code!,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(
                    Icons.copy_outlined,
                  ),
                  label: const Text('复制'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: enabled
                      ? () {
                          _confirmReplace(
                            context,
                            answer!.code!,
                          );
                        }
                      : null,
                  child: const Text(
                    '替换当前文件',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmReplace(
    BuildContext context,
    String code,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: Text(
            '替换 $selectedFile？',
          ),
          content: const Text(
            '只会替换当前选中的文件，'
            '不会运行代码或完成步骤。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  confirmContext,
                  false,
                );
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  confirmContext,
                  true,
                );
              },
              child: const Text('确认替换'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await widget.controller.replaceFileWithAuthorCode(
      selectedFile,
      code,
    );

    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}
