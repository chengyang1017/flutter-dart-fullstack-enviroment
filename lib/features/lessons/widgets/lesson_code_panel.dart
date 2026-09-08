import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../playground/widgets/code_editor_panel.dart';
import '../controller/lesson_controller.dart';
import '../models/code_reference.dart';
import '../models/lesson_step.dart';
import 'code_definition_navigation.dart';
import 'code_references_panel.dart';

class LessonCodePanel extends StatelessWidget {
  const LessonCodePanel({
    super.key,
    required this.controller,
    this.onRun,
    this.onOpenStandardAnswerReference,
  });

  final LessonController controller;
  final Future<void> Function()? onRun;

  /// 当定义位于标准答案时，由 LessonScreen 打开正确步骤和文件。
  final Future<void> Function(
    CodeReference reference,
  )? onOpenStandardAnswerReference;

  Future<void> _openReference(
    BuildContext context,
    CodeReference reference,
  ) async {
    if (!reference.isStandardAnswer) {
      await controller.openReference(reference);
      return;
    }

    final callback = onOpenStandardAnswerReference;

    if (callback == null) {
      _showMessage(
        context,
        '当前页面没有连接标准答案跳转。',
      );
      return;
    }

    await callback(reference);
  }

  Future<void> _showReferences(
    BuildContext context,
  ) async {
    final reference = await showDialog<CodeReference>(
      context: context,
      builder: (dialogContext) {
        return _FindReferencesDialog(
          controller: controller,
          initialSymbol: controller.selectedReferenceSymbol,
        );
      },
    );

    if (reference == null || !context.mounted) {
      return;
    }

    await _openReference(
      context,
      reference,
    );
  }

  Future<void> _goToDefinition(
    BuildContext context,
  ) async {
    final symbol = controller.selectedReferenceSymbol;

    if (symbol.isEmpty) {
      _showMessage(
        context,
        '请先选中名称，或把光标放在名称中。',
      );
      return;
    }

    final definition = await controller.findDefinition(symbol);

    if (!context.mounted) {
      return;
    }

    if (definition == null) {
      _showMessage(
        context,
        '没有找到 $symbol 的定义。',
      );
      return;
    }

    await _openReference(
      context,
      definition,
    );
  }

  void _showMessage(
    BuildContext context,
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currentStep = controller.lesson.steps[controller.currentStepIndex];

    final isUiStep = currentStep.stepType == LessonStepType.ui;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.f12,
        ): () {
          _goToDefinition(context);
        },
        const SingleActivator(
          LogicalKeyboardKey.f12,
          shift: true,
        ): () {
          _showReferences(context);
        },
      },
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      itemCount: controller.availableFiles.length,
                      separatorBuilder: (
                        context,
                        index,
                      ) {
                        return const SizedBox(width: 6);
                      },
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final file = controller.availableFiles[index];

                        return ChoiceChip(
                          label: Text(file),
                          selected: controller.currentFile == file,
                          onSelected: (_) {
                            controller.switchFile(file);
                          },
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: '查找引用（Shift + F12）',
                    onPressed: () {
                      _showReferences(context);
                    },
                    icon: const Icon(
                      Icons.manage_search,
                    ),
                  ),
                  IconButton(
                    tooltip: '跳到定义（F12 / Ctrl + 点击）',
                    onPressed: () {
                      _goToDefinition(context);
                    },
                    icon: const Icon(
                      Icons.account_tree_outlined,
                    ),
                  ),
                  if (isUiStep)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.icon(
                        key: const ValueKey(
                          'lesson-run-button',
                        ),
                        onPressed: controller.isRunning
                            ? null
                            : () async {
                                if (onRun != null) {
                                  await onRun!();
                                } else {
                                  await controller.runCurrentUi();
                                }
                              },
                        icon: controller.isRunning
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.play_arrow,
                              ),
                        label: Text(
                          controller.isRunning ? '渲染中…' : '运行',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: CodeDefinitionCtrlClickRegion(
              lessonController: controller,
              editorController: controller.playground.textController,
              sourceFileName: controller.currentFile,
              sourceStepIndex: controller.currentStepIndex,
              sourceIsStandardAnswer: false,
              onOpenDefinition: (reference) {
                return _openReference(
                  context,
                  reference,
                );
              },
              child: CodeEditorPanel(
                controller: controller.playground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindReferencesDialog extends StatefulWidget {
  const _FindReferencesDialog({
    required this.controller,
    required this.initialSymbol,
  });

  final LessonController controller;
  final String initialSymbol;

  @override
  State<_FindReferencesDialog> createState() {
    return _FindReferencesDialogState();
  }
}

class _FindReferencesDialogState extends State<_FindReferencesDialog> {
  late final TextEditingController _searchController;

  List<CodeReference> _references = const [];

  String _symbol = '';
  bool _hasSearched = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(
      text: widget.initialSymbol,
    );

    if (widget.initialSymbol.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _search();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final symbol = _searchController.text.trim();

    setState(() {
      _symbol = symbol;
      _hasSearched = true;
      _isSearching = true;
    });

    final references = symbol.isEmpty
        ? const <CodeReference>[]
        : await widget.controller.findReferences(symbol);

    if (!mounted) {
      return;
    }

    setState(() {
      _references = references;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.manage_search),
          SizedBox(width: 10),
          Text('查找引用'),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Class、方法或变量名称',
                hintText: '例如 Product',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _isSearching ? null : _search,
                  icon: const Icon(
                    Icons.arrow_forward,
                  ),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (!_isSearching) {
                  _search();
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isSearching
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                            '正在搜索学生代码和标准答案…',
                          ),
                        ],
                      ),
                    )
                  : !_hasSearched
                      ? const Center(
                          child: Text(
                            '输入名称后开始搜索。',
                          ),
                        )
                      : _symbol.isEmpty
                          ? const Center(
                              child: Text(
                                '请输入要查找的名称。',
                              ),
                            )
                          : CodeReferencesPanel(
                              symbol: _symbol,
                              references: _references,
                              onOpenReference: (reference) {
                                Navigator.of(context).pop(reference);
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
