import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:re_editor/re_editor.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/navigation/monaco_route_observer.dart';
import '../../../core/theme/workbench_palette.dart';
import '../controller/lesson_controller.dart';
import '../models/code_reference.dart';
import 'code_definition_navigation.dart';
import '../../../core/monaco/monaco_ctrl_click_bridge.dart';
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
  State<StandardAnswerCodeView> createState() =>
      _StandardAnswerCodeViewState();
}

class _StandardAnswerCodeViewState extends State<StandardAnswerCodeView> {
  static const _darkThemeId = 'lesson-answer-dark';
  static const _lightThemeId = 'lesson-answer-light';
  MonacoController? _monaco;

  MonacoActionRegistration?
    _ctrlClickRegistration;

  static const _options = EditorOptions(
    language: MonacoLanguage.dart,
    theme: MonacoTheme.vsDark,
    fontSize: 15,
    lineHeight: 24,
    fontFamily: 'Cascadia Code, JetBrains Mono, Consolas, monospace',
    fontLigatures: false,
    wordWrap: MonacoWordWrap.off,
    lineNumbers: MonacoLineNumbers.on,
    tabSize: 2,
    insertSpaces: true,
    detectIndentation: false,
    automaticLayout: true,
    padding: MonacoPadding(
      top: 14,
      bottom: 18,
    ),
    scrollBeyondLastLine: false,
    smoothScrolling: false,
    cursorBlinking: CursorBlinking.smooth,
    cursorStyle: CursorStyle.line,
    cursorWidth: 2,
    renderLineHighlight: MonacoLineHighlight.none,
    folding: false,
    overviewRulerBorder: false,
    extra: <String, Object?>{
      'readOnly': true,
      'domReadOnly': true,
      'minimap': <String, Object?>{
        'enabled': false,
      },
      'stickyScroll': <String, Object?>{
        'enabled': false,
      },
      'glyphMargin': false,
      'lineNumbersMinChars': 4,
      'lineDecorationsWidth': 8,
      'overviewRulerLanes': 0,
      'overviewRulerBorder': false,
      'renderLineHighlight': 'none',
      'scrollbar': <String, Object?>{
        'vertical': 'visible',
        'verticalScrollbarSize': 12,
        'horizontal': 'visible',
        'horizontalScrollbarSize': 12,
        'useShadows': false,
      },
    },
  );

  late final CodeLineEditingController _mirrorController;

  Brightness? _appliedBrightness;

  @override
  void initState() {
    super.initState();

    _mirrorController = CodeLineEditingController.fromText(
      widget.code,
      const CodeLineOptions(
        indentSize: 4,
      ),
    );

    _scheduleJump();
  }

  Future<void> _handleCtrlClick(
  Position position,
) async {
  final lines = widget.code
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');

  if (lines.isEmpty) {
    return;
  }

  final lineIndex = (position.line - 1)
      .clamp(
        0,
        lines.length - 1,
      )
      .toInt();

  final columnIndex = (position.column - 1)
      .clamp(
        0,
        lines[lineIndex].length,
      )
      .toInt();

  _mirrorController.selection =
      CodeLineSelection.collapsed(
    index: lineIndex,
    offset: columnIndex,
  );

  final symbol =
      widget.lessonController.symbolAtEditor(
    _mirrorController,
  );

  if (symbol.isEmpty) {
    return;
  }

  final definition =
      await widget.lessonController.findDefinition(
    symbol,
    preferStandardAnswer: true,
  );

  if (!mounted || definition == null) {
    return;
  }

  await widget.onOpenDefinition(
    definition,
  );
}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final brightness = Theme.of(context).brightness;

    if (_monaco != null && _appliedBrightness != brightness) {
      unawaited(_applyTheme());
    }
  }

  @override
  void didUpdateWidget(
    covariant StandardAnswerCodeView oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    final codeChanged = oldWidget.code != widget.code;
    final fileChanged = oldWidget.fileName != widget.fileName;
    final targetChanged = !_sameTarget(
      oldWidget.navigationTarget,
      widget.navigationTarget,
    );

    if (codeChanged) {
      _mirrorController.text = widget.code;
    }

    if (codeChanged || fileChanged) {
      unawaited(_syncDocument());
    } else if (targetChanged) {
      _scheduleJump();
    }
  }

  @override
  void dispose() {
    final monaco = _monaco;
    final ctrlClickRegistration =
        _ctrlClickRegistration;

    if (monaco != null &&
        ctrlClickRegistration != null) {
      unawaited(
        MonacoCtrlClickBridge.uninstall(
          controller: monaco,
          registration:
              ctrlClickRegistration,
        ),
      );
    }

    _mirrorController.dispose();

    super.dispose();
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

  Future<void> _handleReady(
    MonacoController controller,
  ) async {
    _monaco = controller;

    if (mounted) {
      setState(() {});
    }

    await _applyTheme(controller);

    if (!mounted) {
      return;
    }

    await controller.document.setLanguage(
      _languageForPath(widget.fileName),
    );

    await _forceReadOnly(controller);

    _ctrlClickRegistration =
        await MonacoCtrlClickBridge.install(
      controller: controller,
      onCtrlClick: _handleCtrlClick,
    );

    await _jumpToTarget();
  }

  Future<void> _forceReadOnly(
    MonacoController controller,
  ) async {
    await controller.runJavaScript(r'''
(() => {
  const editor = monaco.editor.getEditors()[0];
  if (!editor) return;

  editor.updateOptions({
    readOnly: true,
    domReadOnly: true,
  });
})();
''');
  }

  Future<void> _syncDocument() async {
    final monaco = _monaco;

    if (monaco == null) {
      return;
    }

    await monaco.document.setText(
      widget.code,
    );

    if (!mounted) {
      return;
    }

    await monaco.document.setLanguage(
      _languageForPath(widget.fileName),
    );

    await _forceReadOnly(monaco);

    await _jumpToTarget();
  }

  void _handleSelection(
    Range? range,
  ) {
    if (range == null) {
      return;
    }

    final lines = widget.code
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    if (lines.isEmpty) {
      return;
    }

    final startLine = (range.startLine - 1)
        .clamp(0, lines.length - 1)
        .toInt();

    final endLine = (range.endLine - 1)
        .clamp(0, lines.length - 1)
        .toInt();

    final startColumn = (range.startColumn - 1)
        .clamp(
          0,
          lines[startLine].length,
        )
        .toInt();

    final endColumn = (range.endColumn - 1)
        .clamp(
          0,
          lines[endLine].length,
        )
        .toInt();

    _mirrorController.selection = CodeLineSelection(
      baseIndex: startLine,
      baseOffset: startColumn,
      extentIndex: endLine,
      extentOffset: endColumn,
    );
  }

  void _scheduleJump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_jumpToTarget());
    });
  }

  Future<void> _jumpToTarget() async {
    final target = widget.navigationTarget;
    final monaco = _monaco;

    if (target == null ||
        monaco == null ||
        !target.isStandardAnswer ||
        target.fileName != widget.fileName ||
        target.stepIndex != widget.stepIndex) {
      return;
    }

    final lines = widget.code
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    if (lines.isEmpty) {
      return;
    }

    final lineIndex = (target.line - 1)
        .clamp(
          0,
          lines.length - 1,
        )
        .toInt();

    final columnIndex = (target.column - 1)
        .clamp(
          0,
          lines[lineIndex].length,
        )
        .toInt();

    _mirrorController.selection =
        CodeLineSelection.collapsed(
      index: lineIndex,
      offset: columnIndex,
    );

    await monaco.setSelection(
      Range(
        startLine: lineIndex + 1,
        startColumn: columnIndex + 1,
        endLine: lineIndex + 1,
        endColumn: columnIndex + 1,
      ),
    );

    await monaco.runJavaScript(
      '''
(() => {
  const editor = monaco.editor.getEditors()[0];
  if (!editor) return;

  editor.revealPositionInCenter({
    lineNumber: ${lineIndex + 1},
    column: ${columnIndex + 1},
  });
})();
''',
    );
  }

  Future<void> _applyTheme([
    MonacoController? readyController,
  ]) async {
    final controller =
        readyController ?? _monaco;

    if (controller == null || !mounted) {
      return;
    }

    final dark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final themeId =
        dark ? _darkThemeId : _lightThemeId;

    final themeData = <String, dynamic>{
      'base': dark ? 'vs-dark' : 'vs',
      'inherit': true,
      'rules': <Object?>[],
      'colors': <String, String>{
        'editor.background':
            dark ? '#111318' : '#ffffff',
        'editor.foreground':
            dark ? '#d6deeb' : '#1f2937',
        'editorLineNumber.foreground':
            dark ? '#59606c' : '#8a95a5',
        'editorLineNumber.activeForeground':
            dark ? '#c7ccd6' : '#374151',
        'editor.selectionBackground':
            dark ? '#264f78' : '#bfdbfe',
        'editor.inactiveSelectionBackground':
            dark ? '#1f3b59' : '#dbeafe',
        'editorGutter.background':
            dark ? '#111318' : '#ffffff',
      },
    };

    await controller.defineTheme(
      MonacoThemeDefinition.fromMonacoThemeData(
        themeId,
        themeData,
      ),
    );

    await controller.setTheme(
      MonacoTheme(themeId),
    );

    if (!mounted) {
      return;
    }

    _appliedBrightness =
        Theme.of(context).brightness;
  }

  MonacoLanguage _languageForPath(
    String path,
  ) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.dart')) {
      return MonacoLanguage.dart;
    }

    if (lower.endsWith('.js')) {
      return MonacoLanguage.javascript;
    }

    if (lower.endsWith('.ts')) {
      return MonacoLanguage.typescript;
    }

    if (lower.endsWith('.json')) {
      return MonacoLanguage.json;
    }

    if (lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return MonacoLanguage.yaml;
    }

    if (lower.endsWith('.html')) {
      return MonacoLanguage.html;
    }

    if (lower.endsWith('.css')) {
      return MonacoLanguage.css;
    }

    return MonacoLanguage.plaintext;
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        WorkbenchPalette.of(context);

    return CodeDefinitionCtrlClickRegion(
      lessonController:
          widget.lessonController,
      editorController:
          _mirrorController,
      sourceFileName:
          widget.fileName,
      sourceStepIndex:
          widget.stepIndex,
      sourceIsStandardAnswer: true,
      onOpenDefinition:
          widget.onOpenDefinition,
      child: ColoredBox(
        color: palette.editorBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MonacoEditor(
              initialText: widget.code,
              options: _options,
              autofocus: false,
              showStatusBar: false,
              backgroundColor:
                  palette.editorBackground,
              onReady: (controller) {
                unawaited(
                  _handleReady(controller),
                );
              },
              onSelectionChanged:
                  _handleSelection,
              loadingBuilder: (context) {
                return ColoredBox(
                  color:
                      palette.editorBackground,
                  child: const Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (
                context,
                error,
                stackTrace,
              ) {
                return ColoredBox(
                  color:
                      palette.editorBackground,
                  child: Center(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(
                        24,
                      ),
                      child: SelectableText(
                        context.l10n.tr(
                          'Monaco Editor 启动失败\n$error',
                          'Failed to start Monaco Editor\n$error',
                        ),
                        textAlign:
                            TextAlign.center,
                        style: TextStyle(
                          color: palette.text,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_monaco != null)
              MonacoFocusGuard(
                controller: _monaco!,
                modalRouteObserver:
                    monacoRouteObserver,
              ),
          ],
        ),
      ),
    );
  }
}