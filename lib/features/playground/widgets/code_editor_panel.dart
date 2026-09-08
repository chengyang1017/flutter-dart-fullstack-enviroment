import 'dart:async';

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
  static const _codeFontFamily = 'Consolas';
  static const _codeFontFallback = <String>[
    'Cascadia Mono',
    'Cascadia Code',
    'Courier New',
    'monospace',
    'Microsoft YaHei',
  ];
  static const _relationshipAnalyzer = SingleFileCodeRelationshipAnalyzer();
  static const _analysisDelay = Duration(milliseconds: 160);
  static const _verticalPadding = 14.0;

  Timer? _analysisDebounce;
  List<CodeRelationship> _relationships = const <CodeRelationship>[];
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
      _highlightedRelationship = null;
      _attach(widget.controller);
    }
    if (!oldWidget.wireModeEnabled && widget.wireModeEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _analyzeRelationships();
      });
    } else if (oldWidget.wireModeEnabled && !widget.wireModeEnabled) {
      _analysisDebounce?.cancel();
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
    controller.textController.addListener(_scheduleRelationshipAnalysis);
    controller.workspace.addListener(_scheduleRelationshipAnalysis);
    controller.editorScrollController.verticalScroller.addListener(
      _handleViewportChanged,
    );
    controller.editorScrollController.horizontalScroller.addListener(
      _handleViewportChanged,
    );
  }

  void _detach(PlaygroundController controller) {
    controller.textController.removeListener(_scheduleRelationshipAnalysis);
    controller.workspace.removeListener(_scheduleRelationshipAnalysis);
    controller.editorScrollController.verticalScroller.removeListener(
      _handleViewportChanged,
    );
    controller.editorScrollController.horizontalScroller.removeListener(
      _handleViewportChanged,
    );
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
    if (!path.endsWith('.dart')) {
      setState(() {
        _relationships = const <CodeRelationship>[];
        _highlightedRelationship = null;
      });
      return;
    }

    final result = _relationshipAnalyzer.analyze(source: widget.controller.code);
    setState(() {
      _relationships = result.relationships;
      if (_highlightedRelationship != null &&
          _highlightedRelationship! >= _relationships.length) {
        _highlightedRelationship = null;
      }
    });
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

    // Keep editor metrics close to a desktop IDE. Most importantly, all Latin
    // characters and whitespace should resolve to a monospace font before we
    // fall back to a CJK font, otherwise spaces can look much narrower.
    final codeFontSize = isCompact ? 16.0 : 17.0;
    final lineNumberFontSize = isCompact ? 13.5 : 14.0;
    final lineHeight = codeFontSize * 1.45;
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
    final lineDigits = widget.controller.code.split('\n').length.toString().length;
    final gutterWidth = 48.0 + ((lineDigits - 3).clamp(0, 4) * 8.0);
    final codeOriginX = gutterWidth + 1 + 18;
    final verticalScroller = widget.controller.editorScrollController.verticalScroller;
    final horizontalScroller =
        widget.controller.editorScrollController.horizontalScroller;
    final verticalOffset =
        verticalScroller.hasClients ? verticalScroller.offset : 0.0;
    final horizontalOffset =
        horizontalScroller.hasClients ? horizontalScroller.offset : 0.0;

    final editor = CodeEditor(
      controller: widget.controller.textController,
      scrollController: widget.controller.editorScrollController,
      wordWrap: false,
      autocompleteSymbols: true,
      chunkAnalyzer: NonCodeChunkAnalyzer(),
      autofocus: false,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: _verticalPadding,
      ),
      onChanged: (_) {
        widget.controller.updateCode();
      },
      style: CodeEditorStyle(
        fontFamily: _codeFontFamily,
        fontFamilyFallback: _codeFontFallback,
        fontSize: codeFontSize,
        fontHeight: 1.45,
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
          textStyle: TextStyle(
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: lineNumberFontSize,
            height: 1.45,
            color: const Color(0xff5c6370),
          ),
          focusedTextStyle: TextStyle(
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: lineNumberFontSize,
            height: 1.45,
            color: const Color(0xffabb2bf),
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
              CodeRelationshipOverlay(
                relationships: _relationships,
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
          ],
        ),
      ),
    );
  }
}
