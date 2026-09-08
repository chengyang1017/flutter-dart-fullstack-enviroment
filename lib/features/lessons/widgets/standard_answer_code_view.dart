import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../playground/highlighting/flutter_dart_highlight.dart';
import '../controller/lesson_controller.dart';
import '../models/code_reference.dart';
import 'code_definition_navigation.dart';

class StandardAnswerCodeView extends StatefulWidget {
  const StandardAnswerCodeView({
    super.key,
    required this.lessonController,
    required this.code,
    required this.fileName,
    required this.stepIndex,
    required this.onOpenDefinition,
    this.navigationTarget,
  });

  final LessonController lessonController;
  final String code;
  final String fileName;
  final int stepIndex;
  final CodeReference? navigationTarget;
  final OpenCodeDefinition onOpenDefinition;

  @override
  State<StandardAnswerCodeView> createState() {
    return _StandardAnswerCodeViewState();
  }
}

class _StandardAnswerCodeViewState extends State<StandardAnswerCodeView> {
  late final CodeLineEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = CodeLineEditingController.fromText(
      widget.code,
      const CodeLineOptions(
        indentSize: 4,
      ),
    );

    _scheduleJump();
  }

  @override
  void didUpdateWidget(
    covariant StandardAnswerCodeView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.code != widget.code) {
      _controller.text = widget.code;
    }

    if (oldWidget.code != widget.code ||
        !_sameTarget(
          oldWidget.navigationTarget,
          widget.navigationTarget,
        )) {
      _scheduleJump();
    }
  }

  bool _sameTarget(
    CodeReference? first,
    CodeReference? second,
  ) {
    if (identical(first, second)) {
      return true;
    }

    if (first == null || second == null) {
      return false;
    }

    return first.fileName == second.fileName &&
        first.stepIndex == second.stepIndex &&
        first.line == second.line &&
        first.column == second.column &&
        first.isStandardAnswer == second.isStandardAnswer;
  }

  void _scheduleJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _jumpToTarget();
      }
    });
  }

  void _jumpToTarget() {
    final target = widget.navigationTarget;

    if (target == null ||
        !target.isStandardAnswer ||
        target.fileName != widget.fileName ||
        target.stepIndex != widget.stepIndex) {
      return;
    }

    final lines = _controller.text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    if (lines.isEmpty) {
      return;
    }

    final lineIndex = (target.line - 1).clamp(0, lines.length - 1).toInt();

    final offset =
        (target.column - 1).clamp(0, lines[lineIndex].length).toInt();

    final position = CodeLinePosition(
      index: lineIndex,
      offset: offset,
    );

    _controller.selection = CodeLineSelection.collapsed(
      index: lineIndex,
      offset: offset,
    );

    _controller.makePositionCenterIfInvisible(
      position,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeDefinitionCtrlClickRegion(
      lessonController: widget.lessonController,
      editorController: _controller,
      sourceFileName: widget.fileName,
      sourceStepIndex: widget.stepIndex,
      sourceIsStandardAnswer: true,
      onOpenDefinition: widget.onOpenDefinition,
      child: ColoredBox(
        color: const Color(0xff111318),
        child: CodeEditor(
          controller: _controller,
          readOnly: true,
          showCursorWhenReadOnly: false,
          wordWrap: false,
          autocompleteSymbols: false,
          chunkAnalyzer: NonCodeChunkAnalyzer(),
          autofocus: false,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          style: CodeEditorStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: const [
              'Cascadia Mono',
              'Cascadia Code',
              'Microsoft YaHei',
              'Courier New',
            ],
            fontSize: 15,
            fontHeight: 1.5,
            textColor: const Color(0xffd6deeb),
            backgroundColor: const Color(0xff111318),
            cursorColor: const Color(0xff82aaff),
            cursorWidth: 2,
            cursorLineColor: const Color(0xff28374d),
            selectionColor: const Color(0xff334b68),
            highlightColor: const Color(0xff3b4252),
            codeTheme: CodeHighlightTheme(
              languages: {
                'dart': CodeHighlightThemeMode(
                  mode: flutterDartMode,
                ),
              },
              theme: vscodeDark2026Theme,
            ),
          ),
          indicatorBuilder: (
            context,
            editingController,
            chunkController,
            notifier,
          ) {
            return DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
              textStyle: const TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: [
                  'Cascadia Mono',
                  'Cascadia Code',
                  'Courier New',
                ],
                fontSize: 14,
                height: 1.5,
                color: Color(0xff5c6370),
              ),
              focusedTextStyle: const TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: [
                  'Cascadia Mono',
                  'Cascadia Code',
                  'Courier New',
                ],
                fontSize: 14,
                height: 1.5,
                color: Color(0xffabb2bf),
              ),
            );
          },
          leadingDivider: Container(
            width: 1,
            color: const Color(0xff2c313c),
          ),
        ),
      ),
    );
  }
}
