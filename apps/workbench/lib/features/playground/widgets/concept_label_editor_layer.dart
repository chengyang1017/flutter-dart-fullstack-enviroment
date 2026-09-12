import 'package:flutter/material.dart';

import '../controllers/concept_label_controller.dart';
import '../controllers/playground_controller.dart';

class ConceptLabelEditorLayer extends StatefulWidget {
  const ConceptLabelEditorLayer({
    super.key,
    required this.controller,
    required this.labels,
    required this.enabled,
    required this.child,
  });

  final PlaygroundController controller;
  final ConceptLabelController labels;
  final bool enabled;
  final Widget child;

  @override
  State<ConceptLabelEditorLayer> createState() =>
      _ConceptLabelEditorLayerState();
}

class _ConceptLabelEditorLayerState extends State<ConceptLabelEditorLayer> {
  static const _codeFontFamily = 'Cascadia Code';
  static const _codeFontFallback = <String>[
    'JetBrains Mono',
    'Cascadia Mono',
    'Consolas',
    'Courier New',
    'monospace',
    'Microsoft YaHei',
  ];

  static const _desktopCodeFontSize = 16.0;
  static const _compactCodeFontSize = 15.0;
  static const _codeLineHeight = 24.0;
  static const _lineNumberFontSize = 14.0;
  static const _verticalPadding = 14.0;
  static const _lineNumberWidth = 52.0;
  static const _codeLeftPadding = 12.0;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  int? _revealedLine;
  String _lastSource = '';
  String _lastPath = '';

  String? _cachedRenderSource;
  String? _cachedRenderPath;
  List<String> _cachedLines = const <String>[];
  List<ConceptLabelRule> _cachedReusableRules = const <ConceptLabelRule>[];
  bool _rulesDirty = true;
  int _cachedMaxLineUnits = 1;

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
    widget.labels.addListener(_handleLabelsChanged);

    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _copySourceScrollToLabels();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ConceptLabelEditorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
      _lastSource = '';
      _lastPath = '';
      _revealedLine = null;
    }

    if (!identical(oldWidget.labels, widget.labels)) {
      oldWidget.labels.removeListener(_handleLabelsChanged);
      widget.labels.addListener(_handleLabelsChanged);
      _rulesDirty = true;
      if (widget.enabled) setState(() {});
    }

    if (!oldWidget.enabled && widget.enabled) {
      _revealedLine = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _copySourceScrollToLabels();
      });
    } else if (oldWidget.enabled && !widget.enabled) {
      final vertical = _offsetOf(_verticalController);
      final horizontal = _offsetOf(_horizontalController);
      _revealedLine = null;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _jumpToOffset(
          widget.controller.editorScrollController.verticalScroller,
          vertical,
        );
        _jumpToOffset(
          widget.controller.editorScrollController.horizontalScroller,
          horizontal,
        );
      });
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    widget.labels.removeListener(_handleLabelsChanged);
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _attach(PlaygroundController controller) {
    controller.textController.addListener(_handleSourceChanged);
    controller.workspace.addListener(_handleWorkspaceChanged);
  }

  void _detach(PlaygroundController controller) {
    controller.textController.removeListener(_handleSourceChanged);
    controller.workspace.removeListener(_handleWorkspaceChanged);
  }

  void _handleLabelsChanged() {
    _rulesDirty = true;
    if (!mounted || !widget.enabled) return;
    setState(() {});
  }

  void _handleSourceChanged() {
    if (!mounted || !widget.enabled) return;
    final source = widget.controller.textController.text;
    if (source == _lastSource) return;

    _lastSource = source;
    setState(() {});
  }

  void _handleWorkspaceChanged() {
    if (!mounted || !widget.enabled) return;

    final path = widget.controller.activeFilePath;
    final source = widget.controller.textController.text;
    if (path == _lastPath && source == _lastSource) return;

    if (path != _lastPath) {
      _revealedLine = null;
    }
    _lastPath = path;
    _lastSource = source;
    setState(() {});
  }

  void _toggleReveal(int lineIndex, bool hasLabel) {
    if (!hasLabel) return;

    setState(() {
      _revealedLine = _revealedLine == lineIndex ? null : lineIndex;
    });
  }

  _RenderedLabelLine _renderLine({
    required String sourceLine,
    required int lineIndex,
    required String path,
    required List<ConceptLabelRule> reusableRules,
  }) {
    if (_revealedLine == lineIndex) {
      return _RenderedLabelLine(
        spans: <InlineSpan>[TextSpan(text: sourceLine)],
        hasLabel: true,
      );
    }

    final lineRule = widget.labels.lineRuleFor(
      path: path,
      lineNumber: lineIndex + 1,
    );
    if (lineRule != null && lineRule.source == sourceLine) {
      final indent = _leadingWhitespace(sourceLine);
      return _RenderedLabelLine(
        spans: <InlineSpan>[
          if (indent.isNotEmpty) TextSpan(text: indent),
          _labelSpan(
            label: lineRule.label,
            scope: ConceptLabelScope.line,
          ),
        ],
        hasLabel: true,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    var hasLabel = false;

    while (cursor < sourceLine.length) {
      ConceptLabelRule? nextRule;
      var nextIndex = -1;

      for (final rule in reusableRules) {
        if (rule.source.isEmpty) continue;
        final index = sourceLine.indexOf(rule.source, cursor);
        if (index == -1) continue;

        final shouldReplace = nextIndex == -1 ||
            index < nextIndex ||
            (index == nextIndex &&
                rule.source.length > (nextRule?.source.length ?? 0));

        if (shouldReplace) {
          nextIndex = index;
          nextRule = rule;
        }
      }

      if (nextRule == null) {
        spans.add(TextSpan(text: sourceLine.substring(cursor)));
        break;
      }

      if (nextIndex > cursor) {
        spans.add(TextSpan(text: sourceLine.substring(cursor, nextIndex)));
      }

      spans.add(
        _labelSpan(
          label: nextRule.label,
          scope: ConceptLabelScope.language,
        ),
      );
      hasLabel = true;
      cursor = nextIndex + nextRule.source.length;
    }

    if (sourceLine.isEmpty) {
      spans.add(const TextSpan(text: ' '));
    } else if (spans.isEmpty) {
      spans.add(TextSpan(text: sourceLine));
    }

    return _RenderedLabelLine(
      spans: spans,
      hasLabel: hasLabel,
    );
  }

  WidgetSpan _labelSpan({
    required String label,
    required ConceptLabelScope scope,
  }) {
    final lineScope = scope == ConceptLabelScope.line;

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        key: ValueKey('concept-label-chip-$label'),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: lineScope
              ? const Color(0xff4a356f)
              : const Color(0xff1f456b),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: lineScope
                ? const Color(0xff7556a7)
                : const Color(0xff3473a8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: 13,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: lineScope
                ? const Color(0xfff1e8ff)
                : const Color(0xffdcefff),
          ),
        ),
      ),
    );
  }

  String _leadingWhitespace(String sourceLine) =>
      RegExp(r'^\s*').firstMatch(sourceLine)?.group(0) ?? '';

  void _refreshRenderCache(String source, String path) {
    final sourceChanged = source != _cachedRenderSource;
    final pathChanged = path != _cachedRenderPath;

    if (sourceChanged) {
      _cachedRenderSource = source;
      _cachedLines = source.split('\n');
    }

    if (!sourceChanged && !pathChanged && !_rulesDirty) return;

    _cachedRenderPath = path;
    _cachedReusableRules = widget.labels.reusableRulesForPath(path);

    var maxSourceUnits = 1;
    for (final line in _cachedLines) {
      if (line.length > maxSourceUnits) maxSourceUnits = line.length;
    }

    var maxLabelExpansion = 0;
    final language = ConceptLabelController.languageForPath(path);
    for (final rule in widget.labels.rules) {
      if (rule.language != language) continue;
      final expansion = rule.label.length - rule.source.length;
      if (expansion > maxLabelExpansion) maxLabelExpansion = expansion;
      if (rule.label.length > maxSourceUnits) maxSourceUnits = rule.label.length;
    }

    // Leave room for several expanded reusable labels on the same source line.
    _cachedMaxLineUnits = maxSourceUnits + (maxLabelExpansion * 4) + 8;
    _rulesDirty = false;
  }

  void _copySourceScrollToLabels() {
    _jumpToOffset(
      _verticalController,
      _offsetOf(widget.controller.editorScrollController.verticalScroller),
    );
    _jumpToOffset(
      _horizontalController,
      _offsetOf(widget.controller.editorScrollController.horizontalScroller),
    );
  }

  double _offsetOf(ScrollController controller) {
    return controller.hasClients ? controller.offset : 0.0;
  }

  void _jumpToOffset(ScrollController controller, double offset) {
    if (!controller.hasClients) return;

    final target = offset
        .clamp(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        )
        .toDouble();
    controller.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final codeFontSize =
        isCompact ? _compactCodeFontSize : _desktopCodeFontSize;
    final source = widget.controller.textController.text;
    final path = widget.controller.activeFilePath;
    _refreshRenderCache(source, path);

    final lines = _cachedLines;
    final reusableRules = _cachedReusableRules;

    _lastSource = source;
    _lastPath = path;

    final codeStyle = TextStyle(
      fontFamily: _codeFontFamily,
      fontFamilyFallback: _codeFontFallback,
      fontSize: codeFontSize,
      height: _codeLineHeight / codeFontSize,
      color: const Color(0xffb9c8db),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xff111318),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final estimatedWidth = _lineNumberWidth +
                _codeLeftPadding +
                18 +
                (_cachedMaxLineUnits * codeFontSize * .9);
            final contentWidth = estimatedWidth < constraints.maxWidth
                ? constraints.maxWidth
                : estimatedWidth;

            return SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: constraints.maxHeight,
                child: Scrollbar(
                  controller: _verticalController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    key: ValueKey('concept-label-list-$path'),
                    controller: _verticalController,
                    padding: const EdgeInsets.symmetric(
                      vertical: _verticalPadding,
                    ),
                    itemExtent: _codeLineHeight,
                    cacheExtent: _codeLineHeight * 12,
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final rendered = _renderLine(
                        sourceLine: lines[index],
                        lineIndex: index,
                        path: path,
                        reusableRules: reusableRules,
                      );

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('concept-label-line-${index + 1}'),
                          onTap: rendered.hasLabel
                              ? () => _toggleReveal(
                                    index,
                                    rendered.hasLabel,
                                  )
                              : null,
                          child: SizedBox(
                            width: contentWidth,
                            height: _codeLineHeight,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: _lineNumberWidth,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontFamily: _codeFontFamily,
                                          fontFamilyFallback: _codeFontFallback,
                                          fontSize: _lineNumberFontSize,
                                          height: _codeLineHeight /
                                              _lineNumberFontSize,
                                          color: _revealedLine == index
                                              ? const Color(0xff82aaff)
                                              : const Color(0xff5c6370),
                                          fontWeight: _revealedLine == index
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: _codeLineHeight,
                                  color: const Color(0xff2c313c),
                                ),
                                const SizedBox(width: _codeLeftPadding),
                                RichText(
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  text: TextSpan(
                                    style: codeStyle,
                                    children: rendered.spans,
                                  ),
                                ),
                                const SizedBox(width: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RenderedLabelLine {
  const _RenderedLabelLine({
    required this.spans,
    required this.hasLabel,
  });

  final List<InlineSpan> spans;
  final bool hasLabel;
}
