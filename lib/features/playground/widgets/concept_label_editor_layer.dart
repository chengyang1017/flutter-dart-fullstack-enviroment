import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../controllers/playground_controller.dart';
import '../highlighting/flutter_dart_highlight.dart';

class ConceptLabelEditorLayer extends StatefulWidget {
  const ConceptLabelEditorLayer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final PlaygroundController controller;
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
  static const _codeLeftPadding = 12.0;

  // Reusable label rules are deliberately separated by language. Dart rules
  // never leak into JavaScript, Java, Python, or another future language view.
  static const Map<String, Map<String, String>> _rulesByLanguage = {
    'dart': {
      '@override': '覆盖父类行为',
      'await ': '等待 ',
      'async': '异步',
      'return ': '返回 ',
      'final ': '固定变量 ',
      'const ': '常量 ',
      'var ': '变量 ',
      'late ': '稍后初始化 ',
      'required ': '必填 ',
      'if (': '如果 (',
      'else if (': '否则如果 (',
      'else': '否则',
      'switch (': '按值分支 (',
      'case ': '情况 ',
      'default:': '默认情况:',
      'break;': '结束当前分支;',
      'for (': '循环 (',
      'while (': '条件循环 (',
      'try {': '尝试 {',
      'catch (': '捕获错误 (',
      'throw ': '抛出错误 ',
      'class ': '定义类 ',
      'extends ': '继承 ',
      'implements ': '实现 ',
      'Future<': '异步结果<',
      'Stream<': '数据流<',
      'setState(': '重画当前界面(',
      'notifyListeners()': '通知监听者()',
      'runApp(': '启动 Flutter 应用(',
      'MaterialApp(': 'Flutter 应用外壳(',
      'Scaffold(': '页面骨架(',
      'Navigator.push(': '进入新页面(',
      'Navigator.pop(': '返回上一页(',
      'context.read<': '读取供应器<',
      'context.watch<': '监听供应器<',
      'Provider.of<': '获取供应器<',
      'jsonDecode(': '解析 JSON(',
      'jsonEncode(': '生成 JSON(',
    },
  };

  late final CodeLineEditingController _labelController;
  late final CodeScrollController _labelScrollController;
  bool _updatingLabelController = false;
  int? _revealedLine;
  String _lastSource = '';
  String _lastPath = '';

  @override
  void initState() {
    super.initState();
    _labelController = CodeLineEditingController.fromText(
      '',
      const CodeLineOptions(indentSize: 4),
    );
    _labelScrollController = CodeScrollController();
    _labelController.addListener(_handleLabelSelectionChanged);
    _attach(widget.controller);

    if (widget.enabled) {
      _refreshLabelDocument(resetReveal: true);
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

    if (!oldWidget.enabled && widget.enabled) {
      _refreshLabelDocument(resetReveal: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _copySourceScrollToLabels();
      });
    } else if (oldWidget.enabled && !widget.enabled) {
      final vertical = _offsetOf(_labelScrollController.verticalScroller);
      final horizontal = _offsetOf(_labelScrollController.horizontalScroller);
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
    _labelController.removeListener(_handleLabelSelectionChanged);
    _labelController.dispose();
    _labelScrollController.dispose();
    _labelScrollController.verticalScroller.dispose();
    _labelScrollController.horizontalScroller.dispose();
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

  void _handleSourceChanged() {
    if (!mounted || !widget.enabled) return;
    final source = widget.controller.textController.text;
    if (source == _lastSource) return;
    _refreshLabelDocument();
  }

  void _handleWorkspaceChanged() {
    if (!mounted || !widget.enabled) return;
    final path = widget.controller.activeFilePath;
    final source = widget.controller.textController.text;
    if (path == _lastPath && source == _lastSource) return;
    _refreshLabelDocument(resetReveal: true);
  }

  void _handleLabelSelectionChanged() {
    if (_updatingLabelController || !widget.enabled) return;
    final lineIndex = _labelController.selection.extentIndex;
    final sourceLines = widget.controller.textController.text.split('\n');
    if (lineIndex < 0 || lineIndex >= sourceLines.length) return;
    if (_revealedLine == lineIndex) return;

    _revealedLine = lineIndex;
    _refreshLabelDocument(preserveLine: lineIndex);
  }

  void _refreshLabelDocument({
    bool resetReveal = false,
    int? preserveLine,
  }) {
    final source = widget.controller.textController.text;
    final path = widget.controller.activeFilePath;
    if (resetReveal) _revealedLine = null;

    final nextText = _buildLabelDocument(source: source, path: path);
    _lastSource = source;
    _lastPath = path;

    if (_labelController.text == nextText) return;

    _updatingLabelController = true;
    _labelController.text = nextText;

    final lines = nextText.split('\n');
    if (lines.isNotEmpty) {
      final requestedLine = preserveLine ?? _revealedLine ?? 0;
      final lineIndex = requestedLine.clamp(0, lines.length - 1).toInt();
      final offset = _labelController.selection.extentOffset
          .clamp(0, lines[lineIndex].length)
          .toInt();
      _labelController.selection = CodeLineSelection(
        baseIndex: lineIndex,
        baseOffset: offset,
        extentIndex: lineIndex,
        extentOffset: offset,
      );
    }
    _updatingLabelController = false;
  }

  String _buildLabelDocument({
    required String source,
    required String path,
  }) {
    final language = _languageForPath(path);
    final rules = _rulesByLanguage[language];
    if (rules == null) return source;

    final lines = source.split('\n');
    return List<String>.generate(lines.length, (index) {
      final line = lines[index];
      if (_revealedLine == index) return line;
      return _labelLine(line, rules);
    }).join('\n');
  }

  String _labelLine(String line, Map<String, String> rules) {
    if (line.trim().isEmpty) return line;

    final indentMatch = RegExp(r'^\s*').firstMatch(line);
    final indent = indentMatch?.group(0) ?? '';
    final body = line.substring(indent.length);

    if (body.startsWith('///')) {
      return '$indent文档说明：${body.substring(3).trimLeft()}';
    }
    if (body.startsWith('//')) {
      return '$indent说明：${body.substring(2).trimLeft()}';
    }
    if (body == '{') return '${indent}进入代码块';
    if (body == '}' || body == '};') return '${indent}结束当前结构';
    if (body == ');') return '${indent}结束当前调用';
    if (body == '],') return '${indent}结束列表';

    var result = body;
    for (final rule in rules.entries) {
      result = result.replaceAll(rule.key, rule.value);
    }

    if (result == body) {
      if (body.endsWith('{')) {
        result = '进入 · $body';
      } else if (body.endsWith(');')) {
        result = '执行 · $body';
      }
    }

    return '$indent$result';
  }

  String _languageForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.js') || lower.endsWith('.ts')) return 'javascript';
    if (lower.endsWith('.java')) return 'java';
    if (lower.endsWith('.py')) return 'python';
    return 'plain';
  }

  void _copySourceScrollToLabels() {
    _jumpToOffset(
      _labelScrollController.verticalScroller,
      _offsetOf(widget.controller.editorScrollController.verticalScroller),
    );
    _jumpToOffset(
      _labelScrollController.horizontalScroller,
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
    final fontHeight = _codeLineHeight / codeFontSize;
    final lineNumberHeight = _codeLineHeight / _lineNumberFontSize;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: const Color(0xff111318),
        child: CodeEditor(
          controller: _labelController,
          scrollController: _labelScrollController,
          readOnly: true,
          showCursorWhenReadOnly: false,
          wordWrap: false,
          autocompleteSymbols: false,
          chunkAnalyzer: NonCodeChunkAnalyzer(),
          autofocus: false,
          padding: const EdgeInsets.fromLTRB(
            _codeLeftPadding,
            _verticalPadding,
            18,
            _verticalPadding,
          ),
          style: CodeEditorStyle(
            fontFamily: _codeFontFamily,
            fontFamilyFallback: _codeFontFallback,
            fontSize: codeFontSize,
            fontHeight: fontHeight,
            textColor: const Color(0xffb9c8db),
            backgroundColor: const Color(0xff111318),
            cursorColor: Colors.transparent,
            cursorWidth: 2,
            cursorLineColor: const Color(0xff191c23),
            selectionColor: const Color(0xff26384d),
            highlightColor: const Color(0xff3b4252),
            codeTheme: CodeHighlightTheme(
              languages: {
                'dart': CodeHighlightThemeMode(mode: flutterDartMode),
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
                fontSize: _lineNumberFontSize,
                height: lineNumberHeight,
                color: const Color(0xff5c6370),
              ),
              focusedTextStyle: TextStyle(
                fontFamily: _codeFontFamily,
                fontFamilyFallback: _codeFontFallback,
                fontSize: _lineNumberFontSize,
                height: lineNumberHeight,
                color: const Color(0xff82aaff),
                fontWeight: FontWeight.w700,
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
