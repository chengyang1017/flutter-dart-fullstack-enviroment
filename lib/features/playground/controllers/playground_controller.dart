import 'dart:async';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../../workspace/services/workspace_autosave.dart';
import '../../workspace/services/workspace_snapshot_store.dart';
import '../models/ui_node.dart';
import '../parser/flutter_ui_parser.dart';

enum PreviewDevice {
  androidPhone,
  smallPhone,
  tablet,
  responsive,
}

class PlaygroundController extends ChangeNotifier {
  PlaygroundController({WorkspaceSnapshotStore? workspaceStore}) {
    workspace = WorkspaceController.flutterPlayground(
      mainDartContent: exampleCode,
    );

    if (workspaceStore != null) {
      _workspaceAutosave = WorkspaceAutosave(
        workspace: workspace,
        store: workspaceStore,
        storageKey: workspaceStorageKey,
      );
    }

    _loadedWorkspacePath = workspace.activePath;
    _loadedWorkspaceEntryId = workspace.activeEntry?.id ?? '';
    final restoredEditorState =
        workspace.editorStateForEntryId(_loadedWorkspaceEntryId);

    textController = CodeLineEditingController.fromText(
      workspace.activeEntry?.content ?? '',
      const CodeLineOptions(
        indentSize: 4,
      ),
    );
    _applySelection(restoredEditorState);

    editorScrollController = CodeScrollController(
      verticalScroller: ScrollController(
        initialScrollOffset: restoredEditorState?.verticalOffset ?? 0,
      ),
      horizontalScroller: ScrollController(
        initialScrollOffset: restoredEditorState?.horizontalOffset ?? 0,
      ),
    );

    textController.addListener(_handleEditorValueChanged);
    editorScrollController.verticalScroller.addListener(_handleEditorScroll);
    editorScrollController.horizontalScroller.addListener(_handleEditorScroll);
    workspace.addListener(_handleWorkspaceChanged);
    runCode();
  }

  static const workspaceStorageKey = 'default-playground';
  static const _quickPreviewStart = '// QUICK_PREVIEW_START';
  static const _quickPreviewEnd = '// QUICK_PREVIEW_END';

  static const exampleCode = """import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: PracticeExample(),
        ),
      ),
    ),
  );
}

class PracticeExample extends StatelessWidget {
  const PracticeExample({super.key});

  @override
  Widget build(BuildContext context) {
    return
// QUICK_PREVIEW_START
Container(
    color: Colors.white,
    padding: EdgeInsets.all(24),
    child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
            Icon(
                Icons.language,
                size: 64,
                color: Colors.blue,
            ),
            SizedBox(height: 16),
            Text(
                '万文社',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                ),
            ),
            SizedBox(height: 8),
            Text(
                'Glyphora',
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
                onPressed: null,
                child: Text('开始探索'),
            ),
        ],
    ),
)
// QUICK_PREVIEW_END
    ;
  }
}
""";

  late final CodeLineEditingController textController;
  late final CodeScrollController editorScrollController;
  late final WorkspaceController workspace;

  final FlutterUiParser _parser = FlutterUiParser();

  WorkspaceAutosave? _workspaceAutosave;
  Timer? _debounce;
  String _loadedWorkspacePath = '';
  String _loadedWorkspaceEntryId = '';
  bool _syncingWorkspaceSelection = false;
  bool _restoringEditorUiState = false;
  bool _skipCaptureOnNextWorkspaceSync = false;

  UiNode? root;
  String? error;
  List<String> warnings = [];

  bool isParsing = false;
  bool autoRun = false;
  bool darkPreview = false;

  PreviewDevice device = PreviewDevice.androidPhone;

  String get code => textController.text;
  String get activeFilePath => workspace.activePath;
  bool get restoredBrowserWorkspace =>
      _workspaceAutosave?.restoredSnapshot ?? false;

  bool get canQuickPreview => activeFilePath.endsWith('.dart');

  void selectWorkspaceFile(String path) {
    _captureEditorUiState();
    workspace.openFile(path);
  }

  void closeWorkspaceFile(String path) {
    if (path == workspace.activePath) {
      _captureEditorUiState();
    }
    workspace.closeFile(path);
  }

  void resetWorkspace() {
    _skipCaptureOnNextWorkspaceSync = true;
    workspace.resetWorkspace();
    runCode();
  }

  Future<void> flushWorkspacePersistence() async {
    _captureEditorUiState();
    await _workspaceAutosave?.flush();
  }

  void updateCode() {
    if (_restoringEditorUiState ||
        textController.isComposing) {
      return;
    }

    final path = workspace.activePath;
    if (path.isNotEmpty) {
      workspace.updateFileContentFromEditor(path, textController.text);
    }

    error = null;

    if (!autoRun) {
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      runCode,
    );
  }

  void runCode() {
    _debounce?.cancel();

    isParsing = true;
    error = null;
    warnings = [];

    notifyListeners();

    final currentCode = code.trim();

    if (currentCode.isEmpty) {
      root = null;
      isParsing = false;
      notifyListeners();
      return;
    }

    if (!canQuickPreview) {
      root = null;
      error = 'Quick Preview 只解析 Dart Widget 代码。当前文件：$activeFilePath';
      isParsing = false;
      notifyListeners();
      return;
    }

    final previewSource = _quickPreviewSource(code);

    print(
      'QUICK_PREVIEW DEBUG: '
      'controller=${identityHashCode(this)}, '
      'path=$activeFilePath, '
      'start=${code.contains(_quickPreviewStart)}, '
      'end=${code.contains(_quickPreviewEnd)}, '
      'previewNull=${previewSource == null}, '
      'previewLength=${previewSource?.length}',
    );

    if (previewSource == null) {
      root = null;
      error = null;
    } else {
      try {
        root = _parser.parse(previewSource);
      } catch (exception) {
        root = null;
        error = exception.toString();
      }
    }

    isParsing = false;
    notifyListeners();
  }

  String? _quickPreviewSource(String source) {
  final marked = _markedQuickPreviewSource(source);

  if (marked != null) {
    return marked;
  }

  return _extractBuildReturnWidget(source);
}

String? _markedQuickPreviewSource(
  String source,
) {
  final start = source.indexOf(
    _quickPreviewStart,
  );

  final end = source.indexOf(
    _quickPreviewEnd,
  );

  if (start == -1 ||
      end == -1 ||
      end <= start) {
    return null;
  }

  final value = source
      .substring(
        start + _quickPreviewStart.length,
        end,
      )
      .trim();

  return value.isEmpty ? null : value;
}

String? _extractBuildReturnWidget(
  String source,
) {
  final buildMatch = RegExp(
    r'\bWidget\s+build\s*\([^)]*\)\s*\{',
    multiLine: true,
  ).firstMatch(source);

  if (buildMatch == null) {
    return null;
  }

  final bodyStart = source.indexOf(
    '{',
    buildMatch.start,
  );

  if (bodyStart == -1) {
    return null;
  }

  final bodyEnd = _findMatchingBrace(
    source,
    bodyStart,
  );

  if (bodyEnd == -1) {
    return null;
  }

  final returnMatch = RegExp(
    r'\breturn\b',
  ).firstMatch(
    source.substring(
      bodyStart + 1,
      bodyEnd,
    ),
  );

  if (returnMatch == null) {
    return null;
  }

  final expressionStart =
      bodyStart + 1 + returnMatch.end;

  final expressionEnd =
      _findReturnExpressionEnd(
    source,
    expressionStart,
    bodyEnd,
  );

  if (expressionEnd == -1) {
    return null;
  }

  final value = source
      .substring(
        expressionStart,
        expressionEnd,
      )
      .trim();

  return value.isEmpty ? null : value;
}

int _findMatchingBrace(
  String source,
  int openIndex,
) {
  var depth = 0;
  String? quote;
  var lineComment = false;
  var blockComment = false;

  for (var i = openIndex;
      i < source.length;
      i++) {
    final ch = source[i];
    final next = i + 1 < source.length
        ? source[i + 1]
        : '';

    if (lineComment) {
      if (ch == '\n') {
        lineComment = false;
      }

      continue;
    }

    if (blockComment) {
      if (ch == '*' && next == '/') {
        blockComment = false;
        i++;
      }

      continue;
    }

    if (quote != null) {
      if (ch == '\\') {
        i++;
        continue;
      }

      if (ch == quote) {
        quote = null;
      }

      continue;
    }

    if (ch == '/' && next == '/') {
      lineComment = true;
      i++;
      continue;
    }

    if (ch == '/' && next == '*') {
      blockComment = true;
      i++;
      continue;
    }

    if (ch == "'" || ch == '"') {
      quote = ch;
      continue;
    }

    if (ch == '{') {
      depth++;
      continue;
    }

    if (ch == '}') {
      depth--;

      if (depth == 0) {
        return i;
      }
    }
  }

  return -1;
}

int _findReturnExpressionEnd(
  String source,
  int start,
  int limit,
) {
  var parenDepth = 0;
  var bracketDepth = 0;
  var braceDepth = 0;

  String? quote;
  var lineComment = false;
  var blockComment = false;

  for (var i = start; i < limit; i++) {
    final ch = source[i];
    final next = i + 1 < limit
        ? source[i + 1]
        : '';

    if (lineComment) {
      if (ch == '\n') {
        lineComment = false;
      }

      continue;
    }

    if (blockComment) {
      if (ch == '*' && next == '/') {
        blockComment = false;
        i++;
      }

      continue;
    }

    if (quote != null) {
      if (ch == '\\') {
        i++;
        continue;
      }

      if (ch == quote) {
        quote = null;
      }

      continue;
    }

    if (ch == '/' && next == '/') {
      lineComment = true;
      i++;
      continue;
    }

    if (ch == '/' && next == '*') {
      blockComment = true;
      i++;
      continue;
    }

    if (ch == "'" || ch == '"') {
      quote = ch;
      continue;
    }

    switch (ch) {
      case '(':
        parenDepth++;
        break;

      case ')':
        parenDepth--;
        break;

      case '[':
        bracketDepth++;
        break;

      case ']':
        bracketDepth--;
        break;

      case '{':
        braceDepth++;
        break;

      case '}':
        braceDepth--;
        break;

      case ';':
        if (parenDepth == 0 &&
            bracketDepth == 0 &&
            braceDepth == 0) {
          return i;
        }
        break;
    }
  }

  return -1;
}

  void clearCode() {
    _debounce?.cancel();

    textController.text = '';
    final path = workspace.activePath;
    if (path.isNotEmpty) {
      workspace.updateFileContent(path, '');
    }

    root = null;
    error = null;
    warnings = [];

    notifyListeners();
  }

  void resetExample() {
  _debounce?.cancel();

  _syncingWorkspaceSelection = true;
  _restoringEditorUiState = true;

  workspace.openFile('lib/main.dart');
  workspace.updateFileContent(
    'lib/main.dart',
    exampleCode,
  );

  _loadedWorkspacePath = 'lib/main.dart';
  _loadedWorkspaceEntryId =
      workspace.activeEntry?.id ?? '';

  textController.text = exampleCode;

  root = null;
  error = null;
  warnings = [];

  notifyListeners();

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // re_editor 可能在程序化替换后延迟发出旧值，
    // 下一帧再次确保 Workspace 与 Editor 完全一致。
    workspace.updateFileContent(
      'lib/main.dart',
      exampleCode,
    );

    if (textController.text != exampleCode) {
      textController.text = exampleCode;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncingWorkspaceSelection = false;
      _restoringEditorUiState = false;

      runCode();
    });
  });
}

  void toggleAutoRun() {
    autoRun = !autoRun;

    notifyListeners();

    if (autoRun && !textController.isComposing) {
      runCode();
    }
  }

  void changeDevice(PreviewDevice value) {
    if (device == value) {
      return;
    }

    device = value;
    notifyListeners();
  }

  void togglePreviewTheme() {
    darkPreview = !darkPreview;
    notifyListeners();
  }

  void addWarning(String value) {
    if (warnings.contains(value)) {
      return;
    }

    warnings.add(value);
  }

  void clearWarnings() {
    if (warnings.isEmpty) {
      return;
    }

    warnings = [];
    notifyListeners();
  }

  void _handleEditorValueChanged() {
    if (_restoringEditorUiState) return;
    _captureEditorUiState();
  }

  void _handleEditorScroll() {
    if (_restoringEditorUiState) return;
    _captureEditorUiState();
  }

  void _captureEditorUiState({String? entryId}) {
    if (_restoringEditorUiState) return;
    final id = entryId ?? _loadedWorkspaceEntryId;
    if (id.isEmpty || workspace.entryById(id)?.isFile != true) return;

    final previous = workspace.editorStateForEntryId(id);
    final selection = textController.selection;
    final verticalScroller = editorScrollController.verticalScroller;
    final horizontalScroller = editorScrollController.horizontalScroller;

    workspace.updateEditorStateByEntryId(
      id,
      WorkspaceEditorState(
        baseIndex: selection.baseIndex,
        baseOffset: selection.baseOffset,
        extentIndex: selection.extentIndex,
        extentOffset: selection.extentOffset,
        verticalOffset: verticalScroller.hasClients
            ? verticalScroller.offset
            : previous?.verticalOffset ?? 0,
        horizontalOffset: horizontalScroller.hasClients
            ? horizontalScroller.offset
            : previous?.horizontalOffset ?? 0,
      ),
    );
    _workspaceAutosave?.requestSave();
  }

  void _handleWorkspaceChanged() {
    print(
      'WORKSPACE CHANGE DEBUG: '
      'controller=${identityHashCode(this)}, '
      'path=${workspace.activePath}, '
      'workspaceStart=${workspace.activeEntry?.content.contains(_quickPreviewStart)}, '
      'editorStart=${textController.text.contains(_quickPreviewStart)}, '
      'workspaceLength=${workspace.activeEntry?.content.length}, '
      'editorLength=${textController.text.length}',
    );
    if (_syncingWorkspaceSelection) return;

    final path = workspace.activePath;
    final activeEntry = workspace.activeEntry;
    final workspaceContent = activeEntry?.content ?? '';
    final pathChanged = path != _loadedWorkspacePath;
    final contentChangedOutsideEditor = workspaceContent != textController.text;

    if (!pathChanged && !contentChangedOutsideEditor) {
      notifyListeners();
      return;
    }

    if (_skipCaptureOnNextWorkspaceSync) {
      _skipCaptureOnNextWorkspaceSync = false;
    } else {
      _captureEditorUiState(entryId: _loadedWorkspaceEntryId);
    }

    _syncingWorkspaceSelection = true;
    _restoringEditorUiState = true;
    _loadedWorkspacePath = path;
    _loadedWorkspaceEntryId = activeEntry?.id ?? '';
    textController.text = workspaceContent;
    final restoredState =
        workspace.editorStateForEntryId(_loadedWorkspaceEntryId);
    _applySelection(restoredState);
    root = null;
    error = null;
    warnings = [];
    _syncingWorkspaceSelection = false;

    _restoreScrollAfterLayout(restoredState);
    notifyListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoringEditorUiState = false;
    });
  }

  void _applySelection(WorkspaceEditorState? state) {
    if (state == null || textController.text.isEmpty) {
      textController.selection = const CodeLineSelection.zero();
      return;
    }

    final lines = textController.text.split('\n');
    if (lines.isEmpty) {
      textController.selection = const CodeLineSelection.zero();
      return;
    }

    int clampIndex(int value) => value.clamp(0, lines.length - 1).toInt();
    int clampOffset(int index, int value) =>
        value.clamp(0, lines[index].length).toInt();

    final baseIndex = clampIndex(state.baseIndex);
    final extentIndex = clampIndex(state.extentIndex);
    textController.selection = CodeLineSelection(
      baseIndex: baseIndex,
      baseOffset: clampOffset(baseIndex, state.baseOffset),
      extentIndex: extentIndex,
      extentOffset: clampOffset(extentIndex, state.extentOffset),
    );
  }

  void _restoreScrollAfterLayout(WorkspaceEditorState? state) {
    final verticalTarget = state?.verticalOffset ?? 0;
    final horizontalTarget = state?.horizontalOffset ?? 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_restoringEditorUiState) return;
      _jumpToStoredOffset(
        editorScrollController.verticalScroller,
        verticalTarget,
      );
      _jumpToStoredOffset(
        editorScrollController.horizontalScroller,
        horizontalTarget,
      );
    });
  }

  void _jumpToStoredOffset(ScrollController controller, double target) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final safeTarget = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    controller.jumpTo(safeTarget.toDouble());
  }

  @override
  void dispose() {
    _captureEditorUiState();
    _debounce?.cancel();
    textController.removeListener(_handleEditorValueChanged);
    editorScrollController.verticalScroller.removeListener(_handleEditorScroll);
    editorScrollController.horizontalScroller
        .removeListener(_handleEditorScroll);
    _workspaceAutosave?.dispose();
    workspace.removeListener(_handleWorkspaceChanged);
    editorScrollController.dispose();
    workspace.dispose();
    textController.dispose();

    super.dispose();
  }
}
