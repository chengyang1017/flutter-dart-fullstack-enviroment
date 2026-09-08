import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../controller/lesson_controller.dart';
import '../models/code_reference.dart';
import 'code_references_panel.dart';

typedef OpenCodeDefinition = Future<void> Function(
  CodeReference reference,
);

class CodeDefinitionCtrlClickRegion extends StatefulWidget {
  const CodeDefinitionCtrlClickRegion({
    super.key,
    required this.lessonController,
    required this.editorController,
    required this.sourceFileName,
    required this.sourceStepIndex,
    required this.sourceIsStandardAnswer,
    required this.onOpenDefinition,
    required this.child,
  });

  final LessonController lessonController;
  final CodeLineEditingController editorController;

  /// 当前编辑器正在显示的文件。
  final String sourceFileName;

  /// 当前编辑器内容所属的课程步骤。
  final int sourceStepIndex;

  /// 当前编辑器是否为标准答案编辑器。
  final bool sourceIsStandardAnswer;

  /// 打开学生代码或标准答案中的目标位置。
  ///
  /// 点击调用位置时传入 Class 定义；
  /// 点击 Class 定义并选择某个引用时传入该引用。
  final OpenCodeDefinition onOpenDefinition;

  final Widget child;

  @override
  State<CodeDefinitionCtrlClickRegion> createState() {
    return _CodeDefinitionCtrlClickRegionState();
  }
}

class _CodeDefinitionCtrlClickRegionState
    extends State<CodeDefinitionCtrlClickRegion> {
  bool _ctrlPrimaryPointerDown = false;
  bool _modifierPressed = false;
  bool _isOpening = false;

  @override
  void initState() {
    super.initState();

    HardwareKeyboard.instance.addHandler(
      _handleKeyEvent,
    );

    _updateModifierState();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(
      _handleKeyEvent,
    );

    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    _updateModifierState();
    return false;
  }

  void _updateModifierState() {
    final keyboard = HardwareKeyboard.instance;

    _modifierPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
  }

  void _handlePointerDown(
    PointerDownEvent event,
  ) {
    _updateModifierState();

    final isPrimaryButton = (event.buttons & kPrimaryMouseButton) != 0;

    _ctrlPrimaryPointerDown = isPrimaryButton && _modifierPressed;
  }

  void _handlePointerCancel(
    PointerCancelEvent event,
  ) {
    _ctrlPrimaryPointerDown = false;
  }

  void _handlePointerUp(
    PointerUpEvent event,
  ) {
    final shouldOpen = _ctrlPrimaryPointerDown;

    _ctrlPrimaryPointerDown = false;

    if (!shouldOpen || _isOpening) {
      return;
    }

    _openAfterEditorUpdatesCursor();
  }

  Future<void> _openAfterEditorUpdatesCursor() async {
    // 等 re_editor 完成本次点击造成的光标更新，
    // 再读取光标所在名称。
    await Future<void>.delayed(
      const Duration(milliseconds: 30),
    );

    if (!mounted) {
      return;
    }

    await _openDefinitionOrReferences();
  }

  Future<void> _openDefinitionOrReferences() async {
    final symbol = widget.lessonController.symbolAtEditor(
      widget.editorController,
    );

    if (symbol.isEmpty) {
      _showMessage(
        '请按住 Ctrl，并点击 Class、方法或变量名称。',
      );
      return;
    }

    setState(() {
      _isOpening = true;
    });

    try {
      final definition = await widget.lessonController.findDefinition(
        symbol,
        preferStandardAnswer: widget.sourceIsStandardAnswer,
      );

      if (!mounted) {
        return;
      }

      if (definition == null) {
        _showMessage(
          '没有找到 $symbol 的定义。',
        );
        return;
      }

      if (_isAlreadyAtDefinition(
        definition,
        symbol,
      )) {
        await _showUsageReferences(
          symbol,
        );
        return;
      }

      await widget.onOpenDefinition(
        definition,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpening = false;
        });
      }
    }
  }

  Future<void> _showUsageReferences(
    String symbol,
  ) async {
    final allReferences = await widget.lessonController.findReferences(symbol);

    if (!mounted) {
      return;
    }

    final usageReferences = allReferences
        .where(
          (reference) => !reference.isDefinition,
        )
        .toList();

    if (usageReferences.isEmpty) {
      _showMessage(
        '$symbol 暂时没有被其他地方使用。',
      );
      return;
    }

    final selected = await showDialog<CodeReference>(
      context: context,
      builder: (dialogContext) {
        return _ClassUsageReferencesDialog(
          symbol: symbol,
          references: usageReferences,
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await widget.onOpenDefinition(
      selected,
    );
  }

  bool _isAlreadyAtDefinition(
    CodeReference definition,
    String symbol,
  ) {
    if (definition.isStandardAnswer != widget.sourceIsStandardAnswer ||
        definition.stepIndex != widget.sourceStepIndex ||
        definition.fileName != widget.sourceFileName) {
      return false;
    }

    final selection = widget.editorController.selection;

    final currentLine = selection.extentIndex + 1;

    final currentColumn = selection.extentOffset + 1;

    final definitionStart = definition.column;

    final definitionEnd = definition.column + symbol.length;

    return currentLine == definition.line &&
        currentColumn >= definitionStart &&
        currentColumn <= definitionEnd;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}

class _ClassUsageReferencesDialog extends StatelessWidget {
  const _ClassUsageReferencesDialog({
    required this.symbol,
    required this.references,
  });

  final String symbol;
  final List<CodeReference> references;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.account_tree_outlined,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$symbol 的使用位置',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 820,
        height: 560,
        child: CodeReferencesPanel(
          symbol: symbol,
          references: references,
          onOpenReference: (reference) {
            Navigator.of(context).pop(
              reference,
            );
          },
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
