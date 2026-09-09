import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:re_editor/re_editor.dart';

import '../../../core/navigation/monaco_route_observer.dart';
import '../controllers/concept_label_controller.dart';
import '../controllers/playground_controller.dart';

/// Visible Monaco editor surface that mirrors the existing PlaygroundController
/// while the rest of the IDE migrates away from re_editor incrementally.
class MonacoCodeEditorPanel extends StatefulWidget {
  const MonacoCodeEditorPanel({
    super.key,
    required this.controller,
    this.labels,
    this.labelModeEnabled = false,
    this.wireModeEnabled = false,
  });

  final PlaygroundController controller;
  final ConceptLabelController? labels;
  final bool labelModeEnabled;
  final bool wireModeEnabled;

  @override
  State<MonacoCodeEditorPanel> createState() => _MonacoCodeEditorPanelState();
}

class _MonacoCodeEditorPanelState extends State<MonacoCodeEditorPanel> {
  static const _background = Color(0xff111318);
  static const _themeId = 'code-tutor-dark';

  static const _page = MonacoPageConfig(
    customCss: '''
html, body, #container { background: #111318 !important; }
.monaco-editor,
.monaco-editor-background,
.monaco-editor .margin {
  background-color: #111318 !important;
}
.monaco-editor .margin-view-overlays .line-numbers {
  left: 0 !important;
  width: 46px !important;
  padding: 0 !important;
  color: #626a77 !important;
  text-align: right !important;
  font-variant-numeric: tabular-nums;
}
.monaco-editor .current-line ~ .line-numbers,
.monaco-editor .line-numbers.active-line-number {
  color: #c7ccd6 !important;
}

/* Concept labels stay inside the same Monaco model. */
.monaco-editor .concept-label-hidden-source {
  font-size: 0 !important;
  letter-spacing: 0 !important;
  opacity: 0 !important;
}
.monaco-editor .concept-label-chip {
  border: 1px solid rgb(73 139 184 / 72%);
  border-radius: 5px;
  background: rgb(29 86 126 / 78%);
  color: #dff3ff !important;
  padding: 1px 5px;
  font-family: "Cascadia Code", "JetBrains Mono", Consolas, monospace !important;
  font-size: 12px !important;
  font-weight: 700;
  line-height: 18px !important;
  white-space: pre;
}
.monaco-editor .concept-label-chip-line {
  border-color: rgb(139 111 214 / 78%);
  background: rgb(83 57 142 / 76%);
  color: #eee7ff !important;
}
.monaco-editor .concept-label-chip:hover {
  filter: brightness(1.12);
}
.monaco-scrollable-element > .scrollbar > .slider {
  border-radius: 0 !important;
}
''',
  );

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
    padding: MonacoPadding(top: 42, bottom: 18),
    scrollBeyondLastLine: false,
    smoothScrolling: false,
    cursorBlinking: CursorBlinking.smooth,
    cursorStyle: CursorStyle.line,
    cursorWidth: 2,
    renderLineHighlight: MonacoLineHighlight.none,
    folding: false,
    overviewRulerBorder: false,
    extra: <String, Object?>{
      'minimap': <String, Object?>{
        'enabled': true,
        'side': 'right',
        'size': 'proportional',
        'scale': 1,
        'renderCharacters': true,
        'maxColumn': 100,
        'showSlider': 'always',
      },
      'overviewRulerLanes': 3,
      'overviewRulerBorder': false,
      'scrollbar': <String, Object?>{
        'vertical': 'visible',
        'verticalScrollbarSize': 12,
        'useShadows': false,
      },
      'stickyScroll': <String, Object?>{'enabled': false},
      'glyphMargin': false,
      'lineNumbersMinChars': 4,
      'lineDecorationsWidth': 0,
      'renderLineHighlight': 'none',
      'cursorSmoothCaretAnimation': 'on',
      'roundedSelection': false,
    },
  );

  MonacoController? _monaco;
  final Map<String, MonacoViewState> _viewStates = <String, MonacoViewState>{};

  String _displayedPath = '';
  String _monacoText = '';
  String _selectionSignature = '';
  bool _syncingMirror = false;
  int _syncGeneration = 0;
  late String _initialText;

  @override
  void initState() {
    super.initState();
    _initialText = widget.controller.textController.text;
    _attach(widget.controller);
    _attachLabels(widget.labels);
  }

  @override
  void didUpdateWidget(covariant MonacoCodeEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _viewStates.clear();
      _displayedPath = '';
      _monacoText = '';
      _selectionSignature = '';
      _initialText = widget.controller.textController.text;
      _attach(widget.controller);
      unawaited(_syncFromMirror(forceText: true));
    }

    if (!identical(oldWidget.labels, widget.labels)) {
      _detachLabels(oldWidget.labels);
      _attachLabels(widget.labels);
      unawaited(_syncLabelDecorations(resetReveal: true));
    } else if (oldWidget.labelModeEnabled != widget.labelModeEnabled) {
      unawaited(
        _syncLabelDecorations(resetReveal: !widget.labelModeEnabled),
      );
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    _detachLabels(widget.labels);
    super.dispose();
  }

  void _attach(PlaygroundController controller) {
    controller.textController.addListener(_handleMirrorChanged);
    controller.workspace.addListener(_handleWorkspaceChanged);
  }

  void _detach(PlaygroundController controller) {
    controller.textController.removeListener(_handleMirrorChanged);
    controller.workspace.removeListener(_handleWorkspaceChanged);
  }

  void _attachLabels(ConceptLabelController? labels) {
    labels?.addListener(_handleLabelsChanged);
  }

  void _detachLabels(ConceptLabelController? labels) {
    labels?.removeListener(_handleLabelsChanged);
  }

  void _handleLabelsChanged() {
    unawaited(_syncLabelDecorations());
  }

  void _handleMirrorChanged() {
    if (_syncingMirror) return;
    unawaited(_syncFromMirror());
  }

  void _handleWorkspaceChanged() {
    if (_syncingMirror) return;
    unawaited(_syncFromMirror());
  }

  Future<void> _handleReady(MonacoController controller) async {
    _monaco = controller;
    if (mounted) {
      setState(() {});
    }

    await controller.defineTheme(
      MonacoThemeDefinition.fromMonacoThemeData(
        _themeId,
        const <String, dynamic>{
          'base': 'vs-dark',
          'inherit': true,
          'rules': <Object?>[],
          'colors': <String, String>{
            'editor.background': '#111318',
            'editorLineNumber.foreground': '#59606c',
            'editorLineNumber.activeForeground': '#c7ccd6',
            'editor.selectionBackground': '#264f78',
          },
        },
      ),
    );
    await controller.setTheme(const MonacoTheme(_themeId));

    // Match Code Tutor Studio's Monaco gutter geometry exactly. Monaco decides
    // contentLeft from the current font metrics, line-number digits, and WebView
    // scale, so a hard-coded lineDecorationsWidth can leave the source text
    // touching or overlapping the line numbers. Code Tutor measures contentLeft
    // after boot and adds only the missing decorations width to reach 68 px
    // (56 px gutter + 12 px content gap).
    await controller.runJavaScript(r'''
(() => {
  const editor = monaco.editor.getEditors()[0];
  if (!editor) return;

  const targetContentLeft = 68;
  const layout = editor.getLayoutInfo();
  const currentDecorationsWidth = editor.getOption(
    monaco.editor.EditorOption.lineDecorationsWidth,
  );
  const correctedDecorationsWidth = Math.max(
    0,
    Math.round(
      currentDecorationsWidth + targetContentLeft - layout.contentLeft,
    ),
  );

  if (correctedDecorationsWidth !== currentDecorationsWidth) {
    editor.updateOptions({
      lineDecorationsWidth: correctedDecorationsWidth,
    });
  }
  editor.layout();
})();
''');

    await _installConceptLabelRuntime(controller);

    _displayedPath = widget.controller.activeFilePath;
    _monacoText = widget.controller.textController.text;
    await controller.document.setLanguage(_languageForPath(_displayedPath));
    await _pushMirrorSelection(controller);
    await _syncLabelDecorations(resetReveal: true);
  }

  void _handleMonacoContent(String value) {
    _monacoText = value;

    final mirror = widget.controller.textController;
    if (value == mirror.text) return;

    _syncingMirror = true;
    try {
      mirror.value = mirror.value.copyWith(
        codeLines: CodeLines.fromText(value),
        selection: mirror.selection,
      );
      widget.controller.updateCode();
    } finally {
      _syncingMirror = false;
    }
  }

  void _handleMonacoSelection(Range? range) {
    if (range == null || _syncingMirror) return;

    final lines = widget.controller.textController.text.split('\n');
    if (lines.isEmpty) return;

    final startLine = (range.startLine - 1).clamp(0, lines.length - 1).toInt();
    final endLine = (range.endLine - 1).clamp(0, lines.length - 1).toInt();
    final startColumn =
        (range.startColumn - 1).clamp(0, lines[startLine].length).toInt();
    final endColumn =
        (range.endColumn - 1).clamp(0, lines[endLine].length).toInt();

    final signature = '$startLine:$startColumn:$endLine:$endColumn';
    _selectionSignature = signature;

    _syncingMirror = true;
    try {
      widget.controller.textController.selection = CodeLineSelection(
        baseIndex: startLine,
        baseOffset: startColumn,
        extentIndex: endLine,
        extentOffset: endColumn,
      );
    } finally {
      _syncingMirror = false;
    }
  }

  Future<void> _syncFromMirror({bool forceText = false}) async {
    final monaco = _monaco;
    if (monaco == null) return;

    final generation = ++_syncGeneration;
    final nextPath = widget.controller.activeFilePath;
    final nextText = widget.controller.textController.text;
    final pathChanged = nextPath != _displayedPath;
    final textChanged = forceText || nextText != _monacoText;

    if (pathChanged && _displayedPath.isNotEmpty) {
      try {
        _viewStates[_displayedPath] = await monaco.captureViewState();
      } catch (_) {
        // View state is a convenience only; a bridge hiccup must not block edits.
      }
      if (!mounted || generation != _syncGeneration) return;
    }

    if (textChanged) {
      await monaco.document.setText(nextText);
      if (!mounted || generation != _syncGeneration) return;
      _monacoText = nextText;
    }

    if (pathChanged) {
      await monaco.document.setLanguage(_languageForPath(nextPath));
      if (!mounted || generation != _syncGeneration) return;
      _displayedPath = nextPath;

      final savedView = _viewStates[nextPath];
      if (savedView != null) {
        try {
          await monaco.restoreViewState(savedView);
        } catch (_) {
          await _pushMirrorSelection(monaco);
        }
      } else {
        await _pushMirrorSelection(monaco);
      }
      await _syncLabelDecorations(resetReveal: true);
      return;
    }

    if (textChanged) {
      await _pushMirrorSelection(monaco);
      await _syncLabelDecorations();
    }
  }

  Future<void> _installConceptLabelRuntime(MonacoController controller) async {
    await controller.runJavaScript(r'''
(() => {
  const editor = monaco.editor.getEditors()[0];
  if (!editor || window.__glyphoraConceptLabels) return;

  const state = {
    collection: editor.createDecorationsCollection(),
    payload: { enabled: false, path: '', anchors: [] },
    revealLine: null,
  };

  const injected = (label, className) => ({
    content: ` ${label} `,
    inlineClassName: `concept-label-chip ${className}`,
    inlineClassNameAffectsLetterSpacing: true,
    cursorStops: monaco.editor.InjectedTextCursorStops.Left,
  });

  const render = () => {
    const model = editor.getModel();
    const payload = state.payload;
    if (!model || !payload.enabled) {
      state.collection.clear();
      editor.updateOptions({ readOnly: false });
      return;
    }

    editor.updateOptions({ readOnly: true });
    const decorations = [];
    const occupied = new Map();

    const reserve = (line, start, end) => {
      const ranges = occupied.get(line) ?? [];
      if (ranges.some((range) => start < range.end && end > range.start)) {
        return false;
      }
      ranges.push({ start, end });
      occupied.set(line, ranges);
      return true;
    };

    for (const rule of payload.anchors ?? []) {
      const line = Number(rule.lineNumber);
      const startColumn = Number(rule.startColumn);
      const endColumn = Number(rule.endColumn);
      if (!Number.isFinite(line) ||
          !Number.isFinite(startColumn) ||
          !Number.isFinite(endColumn) ||
          line < 1 ||
          line > model.getLineCount() ||
          startColumn < 1 ||
          endColumn <= startColumn ||
          endColumn > model.getLineMaxColumn(line)) {
        continue;
      }
      if (state.revealLine === line) continue;

      const range = new monaco.Range(
        line,
        startColumn,
        line,
        endColumn,
      );
      const currentSource = model.getValueInRange(range);
      if (currentSource !== rule.source) continue;
      if (!reserve(line, startColumn, endColumn)) continue;

      decorations.push({
        range,
        options: {
          stickiness:
            monaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges,
          inlineClassName: 'concept-label-hidden-source',
          before: injected(
            rule.label,
            rule.lineScoped
              ? 'concept-label-chip-line'
              : 'concept-label-chip-position',
          ),
        },
      });
    }

    state.collection.set(decorations);
  };

  const mouseDisposable = editor.onMouseDown((event) => {
    if (!state.payload.enabled) return;
    const line = event.target?.position?.lineNumber;
    if (!line) return;

    if (state.revealLine === line) {
      event.event?.preventDefault?.();
      state.revealLine = null;
      render();
      return;
    }

    const element = event.target?.element;
    const chip = element?.closest?.('.concept-label-chip');
    if (!chip) return;

    event.event?.preventDefault?.();
    state.revealLine = line;
    render();
  });

  window.__glyphoraConceptLabels = {
    apply(payload) {
      if (state.payload.path !== payload.path) {
        state.revealLine = null;
      }
      state.payload = payload;
      if (!payload.enabled) state.revealLine = null;
      render();
    },
    resetReveal() {
      state.revealLine = null;
      render();
    },
    dispose() {
      state.collection.clear();
      mouseDisposable.dispose();
      editor.updateOptions({ readOnly: false });
      delete window.__glyphoraConceptLabels;
    },
  };
})();
''');
  }

  Future<void> _syncLabelDecorations({bool resetReveal = false}) async {
    final monaco = _monaco;
    if (monaco == null) return;

    final labels = widget.labels;
    final path = widget.controller.activeFilePath;
    final enabled = widget.labelModeEnabled && labels != null;

    final resolved = enabled
        ? labels!.resolveLabelsForSource(
            path: path,
            sourceText: widget.controller.textController.text,
          )
        : const <ResolvedConceptLabel>[];

    final anchors = resolved
        .map(
          (match) => <String, Object?>{
            'id': match.rule.id,
            'source': match.source,
            'label': match.rule.label,
            'lineNumber': match.lineNumber,
            'startColumn': match.startColumn + 1,
            'endColumn': match.endColumn + 1,
            'lineScoped': match.lineScoped,
          },
        )
        .toList(growable: false);

    final payload = jsonEncode(<String, Object?>{
      'enabled': enabled,
      'path': path,
      'anchors': anchors,
    });

    if (resetReveal) {
      await monaco.runJavaScript(
        'window.__glyphoraConceptLabels?.resetReveal?.();',
      );
    }
    await monaco.runJavaScript(
      'window.__glyphoraConceptLabels?.apply($payload);',
    );
  }

  Future<void> _pushMirrorSelection(MonacoController monaco) async {
    final selection = widget.controller.textController.selection;
    final base = (line: selection.baseIndex, column: selection.baseOffset);
    final extent =
        (line: selection.extentIndex, column: selection.extentOffset);

    final baseBeforeExtent = base.line < extent.line ||
        (base.line == extent.line && base.column <= extent.column);
    final start = baseBeforeExtent ? base : extent;
    final end = baseBeforeExtent ? extent : base;
    final signature = '${start.line}:${start.column}:${end.line}:${end.column}';
    if (signature == _selectionSignature) return;

    _selectionSignature = signature;
    await monaco.setSelection(
      Range(
        startLine: start.line + 1,
        startColumn: start.column + 1,
        endLine: end.line + 1,
        endColumn: end.column + 1,
      ),
    );
  }

  MonacoLanguage _languageForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return MonacoLanguage.dart;
    if (lower.endsWith('.js')) return MonacoLanguage.javascript;
    if (lower.endsWith('.ts')) return MonacoLanguage.typescript;
    if (lower.endsWith('.json')) return MonacoLanguage.json;
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return MonacoLanguage.yaml;
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return MonacoLanguage.html;
    }
    if (lower.endsWith('.css')) return MonacoLanguage.css;
    if (lower.endsWith('.md')) return MonacoLanguage.markdown;
    if (lower.endsWith('.java')) return MonacoLanguage.java;
    if (lower.endsWith('.kt') || lower.endsWith('.kts')) {
      return MonacoLanguage.kotlin;
    }
    if (lower.endsWith('.py')) return MonacoLanguage.python;
    if (lower.endsWith('.c') || lower.endsWith('.h')) return MonacoLanguage.c;
    if (lower.endsWith('.cpp') ||
        lower.endsWith('.cc') ||
        lower.endsWith('.hpp')) {
      return MonacoLanguage.cpp;
    }
    if (lower.endsWith('.cs')) return MonacoLanguage.csharp;
    if (lower.endsWith('.xml')) return MonacoLanguage.xml;
    if (lower.endsWith('.ps1')) return MonacoLanguage.powershell;
    if (lower.endsWith('.sh')) return MonacoLanguage.shell;
    if (lower.endsWith('.sql')) return MonacoLanguage.sql;
    return MonacoLanguage.plaintext;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MonacoEditor(
            initialText: _initialText,
            options: _options,
            page: _page,
            autofocus: false,
            showStatusBar: false,
            backgroundColor: _background,
            contentDebounce: const Duration(milliseconds: 24),
            onReady: (controller) {
              unawaited(_handleReady(controller));
            },
            onContentChanged: _handleMonacoContent,
            onSelectionChanged: _handleMonacoSelection,
            loadingBuilder: (context) => const ColoredBox(
              color: _background,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: _background,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(
                    'Monaco Editor 启动失败\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xffd7dae0)),
                  ),
                ),
              ),
            ),
          ),
          if (_monaco != null)
            MonacoFocusGuard(
              controller: _monaco!,
              modalRouteObserver: monacoRouteObserver,
            ),
        ],
      ),
    );
  }
}
