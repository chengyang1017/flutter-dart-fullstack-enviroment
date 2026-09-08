import 'dart:async';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../controllers/playground_controller.dart';
import '../highlighting/flutter_dart_highlight.dart';
import '../services/single_file_code_relationship_analyzer.dart';
import 'code_relationship_overlay.dart';

class CodeEditorPanel extends StatefulWidget {
  const CodeEditorPanel({
    super.key,
    required this.controller,
    this.wireModeEnabled = false,
  });

  final PlaygroundController controller;
  final bool wireModeEnabled;

  @override
  State<CodeEditorPanel> createState() => _CodeEditorPanelState();
}

class _CodeEditorPanelState extends State<CodeEditorPanel> {
  // Keep the editor on the same kind of monospace stack used by Monaco/VS Code.
  // Cascadia has a wider, more IDE-like cell than the previous Consolas-first
  // setup, so a single blank space no longer looks unnaturally compressed.
  static const _codeFontFamily = 'Cascadia Code';
  static const _codeFontFallback = <String>[
    'JetBrains Mono',
    'Cascadia Mono',
    'Consolas',
    'Courier New',
    'monospace',
    'Microsoft YaHei',
  ];
  static const _relationshipAnalyzer = SingleFileCodeRelationshipAnalyzer();
  static const _analysisDelay = Duration(milliseconds: 160);
  static const _verticalPadding = 14.0;
  static const _normalCodeLeftPadding = 12.0;
  static const _desktopCodeFontSize = 16.0;
  static const _compactCodeFontSize = 15.0;
  static const _codeLineHeight = 24.0;
  static const _lineNumberFontSize = 14.0;
  static const _wireOverlayWidth = 166.0;
  static const _wireScrollbarInset = 16.0;

  Timer? _analysisDebounce;
  List<CodeRelationship> _relationships = const <CodeRelationship>[];
  List<_CallableRange> _callableRanges = const <_CallableRange>[];
  _CallableRange? _activeCallable;
  String _lastAnalyzedSource = '';
  int? _highlightedRelationship;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    if (widget.wireModeEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyzeRelationships();
      });
    }
  }

  @override
  void didUpdateWidget(covariant CodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _analysisDebounce?.cancel();
      _relationships = const <CodeRelationship>[];
      _callableRanges = const <_CallableRange>[];
      _activeCallable = null;
      _lastAnalyzedSource = '';
      _highlightedRelationship = null;
      _attach(widget.controller);
    }
    if (!oldWidget.wireModeEnabled && widget.wireModeEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyzeRelationships();
      });
    } else if (oldWidget.wireModeEnabled && !widget.wireModeEnabled) {
      _analysisDebounce?.cancel();
      _activeCallable = null;
      _highlightedRelationship = null;
    }
  }

  @override
  void dispose() {
    _analysisDebounce?.cancel();
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(PlaygroundController controller) {
    controller.textController.addListener(_handleEditorControllerChanged);
    controller.workspace.addListener(_handleWorkspaceChanged);
    controller.editorScrollController.verticalScroller.addListener(
      _handleViewportChanged,
    );
    controller.editorScrollController.horizontalScroller.addListener(
      _handleViewportChanged,
    );
  }

  void _detach(PlaygroundController controller) {
    controller.textController.removeListener(_handleEditorControllerChanged);
    controller.workspace.removeListener(_handleWorkspaceChanged);
    controller.editorScrollController.verticalScroller.removeListener(
      _handleViewportChanged,
    );
    controller.editorScrollController.horizontalScroller.removeListener(
      _handleViewportChanged,
    );
  }

  void _handleEditorControllerChanged() {
    if (!mounted || !widget.wireModeEnabled) return;
    _updateActiveCallable();

    final source = widget.controller.textController.text;
    if (source == _lastAnalyzedSource) return;
    _scheduleRelationshipAnalysis();
  }

  void _handleWorkspaceChanged() {
    if (!mounted || !widget.wireModeEnabled) return;
    _lastAnalyzedSource = '';
    _scheduleRelationshipAnalysis();
  }

  void _scheduleRelationshipAnalysis() {
    if (!widget.wireModeEnabled) return;
    _analysisDebounce?.cancel();
    _analysisDebounce = Timer(_analysisDelay, _analyzeRelationships);
  }

  void _handleViewportChanged() {
    if (!mounted || !widget.wireModeEnabled) return;
    setState(() {});
  }

  void _analyzeRelationships() {
    if (!mounted || !widget.wireModeEnabled) return;
    final path = widget.controller.activeFilePath;
    final source = widget.controller.textController.text;

    if (!path.endsWith('.dart')) {
      setState(() {
        _relationships = const <CodeRelationship>[];
        _callableRanges = const <_CallableRange>[];
        _activeCallable = null;
        _lastAnalyzedSource = source;
        _highlightedRelationship = null;
      });
      return;
    }

    final result = _relationshipAnalyzer.analyze(source: source);
    final callableRanges = _collectCallableRanges(source);
    final activeCallable = _findActiveCallable(source, callableRanges);

    setState(() {
      _relationships = result.relationships;
      _callableRanges = callableRanges;
      _activeCallable = activeCallable;
      _lastAnalyzedSource = source;
      if (_highlightedRelationship != null &&
          _highlightedRelationship! >= _relationships.length) {
        _highlightedRelationship = null;
      }
    });
  }

  List<_CallableRange> _collectCallableRanges(String source) {
    if (source.trim().isEmpty) return const <_CallableRange>[];
    final unit = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit;
    final visitor = _CallableRangeVisitor();
    unit.accept(visitor);
    visitor.ranges.sort((a, b) => a.length.compareTo(b.length));
    return List<_CallableRange>.unmodifiable(visitor.ranges);
  }

  void _updateActiveCallable() {
    final source = widget.controller.textController.text;
    final next = _findActiveCallable(source, _callableRanges);
    final current = _activeCallable;
    if (current?.start == next?.start && current?.end == next?.end) return;
    setState(() {
      _activeCallable = next;
      _highlightedRelationship = null;
    });
  }

  _CallableRange? _findActiveCallable(
    String source,
    List<_CallableRange> ranges,
  ) {
    if (ranges.isEmpty || source.isEmpty) return null;
    final cursorOffset = _selectionOffset(source);
    for (final range in ranges) {
      if (cursorOffset >= range.start && cursorOffset <= range.end) {
        return range;
      }
    }
    return null;
  }

  int _selectionOffset(String source) {
    final lines = source.split('\n');
    if (lines.isEmpty) return 0;
    final selection = widget.controller.textController.selection;
    final lineIndex = selection.extentIndex.clamp(0, lines.length - 1).toInt();
    final columnIndex = selection.extentOffset
        .clamp(0, lines[lineIndex].length)
        .toInt();

    var offset = 0;
    for (var i = 0; i < lineIndex; i++) {
      offset += lines[i].length + 1;
    }
    return (offset + columnIndex).clamp(0, source.length).toInt();
  }

  Set<int> _activeRelationshipIndexes() {
    final callable = _activeCallable;
    if (callable == null) return const <int>{};

    final result = <int>{};
    for (var index = 0; index < _relationships.length; index++) {
      final relationship = _relationships[index];
      final sourceInside = relationship.source.offset >= callable.start &&
          relationship.source.offset <= callable.end;
      final targetInside = relationship.target.offset >= callable.start &&
          relationship.target.offset <= callable.end;
      if (sourceInside || targetInside) result.add(index);
    }
    return result;
  }

  int _focusLine() {
    final lineCount = widget.controller.textController.text.split('\n').length;
    if (lineCount <= 0) return 1;
    return (widget.controller.textController.selection.extentIndex + 1)
        .clamp(1, lineCount)
        .toInt();
  }

  void _jumpTo(CodeRelationshipAnchor anchor) {
    final editor = widget.controller.textController;
    final lines = editor.text.split('\n');
    if (lines.isEmpty) return;
    final lineIndex = (anchor.line - 1).clamp(0, lines.length - 1).toInt();
    final columnIndex =
        (anchor.column - 1).clamp(0, lines[lineIndex].length).toInt();
    final endOffset = (columnIndex + anchor.length)
        .clamp(columnIndex, lines[lineIndex].length)
        .toInt();
    editor.selection = CodeLineSelection(
      baseIndex: lineIndex,
      baseOffset: columnIndex,
      extentIndex: lineIndex,
      extentOffset: endOffset,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;

    final codeFontSize =
        isCompact ? _compactCodeFontSize : _desktopCodeFontSize;
    const lineNumberFontSize = _lineNumberFontSize;
    const lineHeight = _codeLineHeight;
    final fontHeight = lineHeight / codeFontSize;
    final lineNumberFontHeight = lineHeight / lineNumberFontSize;
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          fontFamily: _codeFontFamily,
          fontFamilyFallback: _codeFontFallback,
          fontSize: codeFontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final charWidth = textPainter.width;

    // Match re_editor's DefaultCodeLineNumber layout exactly: its width is
    // the measured width of a zero-filled string with at least three digits.
    // Do not estimate this gutter with fixed pixels, otherwise every wire
    // anchor drifts horizontally away from the real token.
    final lineCount = widget.controller.textController.text.split('\n').length;
    final rawLineDigits = lineCount.toString().length;
    final lineNumberDigits = rawLineDigits < 3 ? 3 : rawLineDigits;
    final lineNumberPainter = TextPainter(
      text: TextSpan(
        text: List<String>.filled(lineNumberDigits, '0').join(),
        style: const TextStyle(
          fontFamily: _codeFontFamily,
          fontFamilyFallback: _codeFontFallback,
          fontSize: lineNumberFontSize,
          height: lineNumberFontHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineNumberWidth = lineNumberPainter.width;

    const codeLeftPadding = _normalCodeLeftPadding;
    final codeOriginX = lineNumberWidth + 1 + codeLeftPadding;
    final verticalScroller = widget.controller.editorScrollController.verticalScroller;
    final horizontalScroller =
        widget.controller.editorScrollController.horizontalScroller;
    final verticalOffset =
        verticalScroller.hasClients ? verticalScroller.offset : 0.0;
    final horizontalOffset =
        horizontalScroller.hasClients ? horizontalScroller.offset : 0.0;
    final codeRightPadding = widget.wireModeEnabled
        ? _wireOverlayWidth + _wireScrollbarInset + 8
        : 18.0;

    final editor = CodeEditor(
      controller: widget.controller.textController,
      scrollController: widget.controller.editorScrollController,
      wordWrap: false,
      autocompleteSymbols: true,
      chunkAnalyzer: NonCodeChunkAnalyzer(),
      autofocus: false,
      padding: EdgeInsets.fromLTRB(
        codeLeftPadding,
        _verticalPadding,
        codeRightPadding,
        _verticalPadding,
      ),
      onChanged: (_) {
        widget.controller.updateCode();
      },
      style: CodeEditorStyle(
        fontFamily: _codeFontFamily,
        fontFamilyFallback: _codeFontFallback,
        fontSize: codeFontSize,
        fontHeight: fontHeight,
        textColor: const Color(0xffd6deeb),
        backgroundColor: const Color(0xff111318),
        cursorColor: const Color(0xff82aaff),
        cursorWidth: 2,
        cursorLineColor: const Color(0xff191c23),
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
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: lineNumberFontSize,
            height: lineNumberFontHeight,
            color: Color(0xff5c6370),
          ),
          focusedTextStyle: const TextStyle(
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: lineNumberFontSize,
            height: lineNumberFontHeight,
            color: Color(0xffabb2bf),
          ),
        );
      },
      leadingDivider: Container(
        width: 1,
        color: const Color(0xff2c313c),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xff111318),
        child: Stack(
          fit: StackFit.expand,
          children: [
            editor,
            if (widget.wireModeEnabled)
              Positioned.fill(
                child: CodeRelationshipOverlay(
                  relationships: _relationships,
                  activeRelationshipIndexes: _activeRelationshipIndexes(),
                  focusLine: _focusLine(),
                  codeOriginX: codeOriginX,
                  charWidth: charWidth,
                  lineHeight: lineHeight,
                  verticalPadding: _verticalPadding,
                  verticalScrollOffset: verticalOffset,
                  horizontalScrollOffset: horizontalOffset,
                  highlightedIndex: _highlightedRelationship,
                  onHoverRelationship: (index) {
                    if (!mounted || _highlightedRelationship == index) return;
                    setState(() => _highlightedRelationship = index);
                  },
                  onJumpTo: _jumpTo,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallableRange {
  const _CallableRange({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;

  int get length => end - start;
}

class _CallableRangeVisitor extends RecursiveAstVisitor<void> {
  final List<_CallableRange> ranges = <_CallableRange>[];

  void _add(AstNode node) {
    ranges.add(
      _CallableRange(
        start: node.offset,
        end: node.end,
      ),
    );
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(node);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _add(node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _add(node);
    super.visitConstructorDeclaration(node);
  }
}
