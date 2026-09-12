import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import '../../playground/controllers/playground_controller.dart';
import '../checking/lesson_checker.dart';
import '../data/author_answer_repository.dart';
import '../data/lesson_progress_store.dart';
import '../models/code_reference.dart';
import '../models/lesson.dart';
import '../models/lesson_check_result.dart';
import '../models/lesson_step.dart';

class LessonController extends ChangeNotifier {
  LessonController({
    required this.lesson,
    required this.store,
    AuthorAnswerRepository? answerRepository,
    LessonChecker? checker,
  })  : answerRepository = answerRepository ?? AuthorAnswerRepository(),
        checker = checker ?? LessonChecker(),
        playground = PlaygroundController() {
    playground.addListener(_relay);
    _restore();
  }

  Lesson lesson;
  final LessonProgressStore store;
  final AuthorAnswerRepository answerRepository;
  final LessonChecker checker;
  final PlaygroundController playground;

  final Map<String, String?> _standardAnswerCodeCache = {};

  int currentStepIndex = 0;
  int visibleHintCount = 0;
  int attempts = 0;

  bool viewedAnswer = false;
  bool isRunning = false;
  bool isChecking = false;

  Set<String> completedSteps = {};
  Map<String, String> lastCode = {};
  Map<String, String> fileCodes = {};

  late String currentFile;

  LessonCheckResult? checkResult;

  bool get isComplete =>
      lesson.steps.isNotEmpty &&
      lesson.steps.every(
        (step) => completedSteps.contains(step.id),
      );

  void replaceLesson(Lesson nextLesson) {
    if (nextLesson.id != lesson.id) return;
    lesson = nextLesson;
    if (lesson.steps.isNotEmpty) {
      currentStepIndex = currentStepIndex.clamp(0, lesson.steps.length - 1);
    } else {
      currentStepIndex = 0;
    }
    notifyListeners();
  }

  String get selectedReferenceSymbol {
    return symbolAtEditor(
      playground.textController,
    );
  }

  /// 读取任意 re_editor 编辑器当前选中或光标所在的标识符。
  String symbolAtEditor(
    CodeLineEditingController editor,
  ) {
    final selected = editor.selectedText.trim();

    if (_isValidIdentifier(selected)) {
      return selected;
    }

    final normalizedText =
        editor.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final lines = normalizedText.split('\n');

    if (lines.isEmpty) {
      return '';
    }

    final selection = editor.selection;

    final lineIndex = selection.extentIndex.clamp(0, lines.length - 1).toInt();

    final line = lines[lineIndex];

    final cursorOffset = selection.extentOffset.clamp(0, line.length).toInt();

    var start = cursorOffset;
    var end = cursorOffset;

    while (start > 0 &&
        _isIdentifierCodeUnit(
          line.codeUnitAt(start - 1),
        )) {
      start--;
    }

    while (end < line.length &&
        _isIdentifierCodeUnit(
          line.codeUnitAt(end),
        )) {
      end++;
    }

    final symbol = line.substring(start, end);

    return _isValidIdentifier(symbol) ? symbol : '';
  }

  void _relay() {
    notifyListeners();
  }

  void _restore() {
    final data = store.load(lesson.id);

    currentStepIndex =
        (data['currentStep'] as int?)?.clamp(0, lesson.steps.length - 1) ?? 0;

    completedSteps = Set<String>.from(
      data['completedSteps'] as List? ?? const [],
    );

    lastCode = Map<String, String>.from(
      data['lastCode'] as Map? ?? const {},
    );

    fileCodes = Map<String, String>.from(
      data['fileCodes'] as Map? ?? const {},
    );

    attempts = data['attempts'] as int? ?? 0;
    viewedAnswer = data['viewedAnswer'] as bool? ?? false;

    _loadStep();
  }

  void _loadStep() {
    final step = lesson.steps[currentStepIndex];

    currentFile = step.currentFile;

    final code =
        fileCodes[currentFile] ?? lastCode[step.id] ?? step.starterCode;

    fileCodes.putIfAbsent(
      currentFile,
      () => code,
    );

    playground.textController.text = code;

    _refreshPreview();

    visibleHintCount = 0;
    checkResult = null;
  }

  Future<void> _save() {
    return store.save(
      lesson.id,
      {
        'currentStep': currentStepIndex,
        'completedSteps': completedSteps.toList(),
        'lastCode': lastCode,
        'fileCodes': fileCodes,
        'attempts': attempts,
        'viewedAnswer': viewedAnswer,
      },
    );
  }

  Future<void> check() async {
    if (isChecking) {
      return;
    }

    isChecking = true;
    notifyListeners();

    attempts++;
    _captureCode();

    final step = lesson.steps[currentStepIndex];

    try {
      if (step.stepType == LessonStepType.ui) {
        playground.runCode();
      }

      checkResult = checker.checkStep(
        playground.code,
        step,
      );

      if (checkResult!.passed) {
        completedSteps.add(step.id);
      }

      await _save();
    } finally {
      isChecking = false;
      notifyListeners();
    }
  }

  Future<bool> runCurrentUi() async {
    if (isRunning ||
        lesson.steps[currentStepIndex].stepType != LessonStepType.ui) {
      return false;
    }

    isRunning = true;
    notifyListeners();

    try {
      await Future<void>.delayed(Duration.zero);

      playground.runCode();

      return playground.error == null;
    } finally {
      isRunning = false;
      notifyListeners();
    }
  }

  void showNextHint() {
    final max = lesson.steps[currentStepIndex].hints.length;

    if (visibleHintCount < max) {
      visibleHintCount++;
    }

    notifyListeners();
  }

  Future<void> markAnswerViewed() async {
    viewedAnswer = true;
    await _save();
    notifyListeners();
  }

  Future<void> replaceFileWithAuthorCode(
    String file,
    String code,
  ) async {
    _captureCode();

    currentFile = file;
    fileCodes[file] = code;
    playground.textController.text = code;
    lastCode[lesson.steps[currentStepIndex].id] = code;

    await _save();
    notifyListeners();
  }

  List<String> get availableFiles {
    final files = <String>{};

    for (final step in lesson.steps) {
      files.add(step.currentFile);
      files.addAll(step.relatedFiles);
      files.addAll(step.standardAnswerAssets.keys);
    }

    return files.toList(growable: false);
  }

  Future<void> switchFile(String file) async {
    if (file == currentFile || !availableFiles.contains(file)) {
      return;
    }

    _captureCode();

    currentFile = file;
    playground.textController.text = _codeForFile(file);

    fileCodes.putIfAbsent(
      file,
      () => playground.textController.text,
    );

    _refreshPreview();

    await _save();
    notifyListeners();
  }

  void _captureCode() {
    final code = playground.code;

    fileCodes[currentFile] = code;
    lastCode[lesson.steps[currentStepIndex].id] = code;
  }

  void _refreshPreview() {
    if (lesson.steps[currentStepIndex].stepType == LessonStepType.ui) {
      playground.runCode();
    } else {
      playground.root = null;
      playground.error = null;
    }
  }

  Future<void> goTo(int index) async {
    if (index < 0 || index >= lesson.steps.length) {
      return;
    }

    _captureCode();

    currentStepIndex = index;
    _loadStep();

    await _save();
    notifyListeners();
  }

  Future<void> restartLesson() async {
    currentStepIndex = 0;
    completedSteps.clear();
    lastCode.clear();
    fileCodes.clear();

    attempts = 0;
    viewedAnswer = false;

    _loadStep();

    await _save();
    notifyListeners();
  }

  /// 搜索学生代码与全部标准答案。
  Future<List<CodeReference>> findReferences(
    String symbol,
  ) async {
    final normalizedSymbol = symbol.trim();

    if (!_isValidIdentifier(normalizedSymbol)) {
      return const [];
    }

    _captureCode();

    final documents = <_ReferenceDocument>[];
    final addedStudentFiles = <String>{};

    for (final entry in fileCodes.entries) {
      final stepIndex = _stepIndexContainingFile(entry.key) ?? currentStepIndex;

      documents.add(
        _ReferenceDocument(
          fileName: entry.key,
          code: entry.value,
          stepIndex: stepIndex,
          isStandardAnswer: false,
        ),
      );

      addedStudentFiles.add(entry.key);
    }

    for (var index = 0; index < lesson.steps.length; index++) {
      final step = lesson.steps[index];

      if (!addedStudentFiles.contains(step.currentFile)) {
        documents.add(
          _ReferenceDocument(
            fileName: step.currentFile,
            code: lastCode[step.id] ?? step.starterCode,
            stepIndex: index,
            isStandardAnswer: false,
          ),
        );

        addedStudentFiles.add(step.currentFile);
      }

      for (final answerEntry in step.standardAnswerAssets.entries) {
        final answerCode = await _loadStandardAnswerCode(
          answerEntry.value,
        );

        if (answerCode == null || answerCode.isEmpty) {
          continue;
        }

        documents.add(
          _ReferenceDocument(
            fileName: answerEntry.key,
            code: answerCode,
            stepIndex: index,
            isStandardAnswer: true,
          ),
        );
      }
    }

    final escapedSymbol = RegExp.escape(normalizedSymbol);

    final symbolPattern = RegExp(
      r'\b' + escapedSymbol + r'\b',
    );

    final definitionPattern = RegExp(
      r'\b(class|enum|mixin|extension|typedef)\s+' + escapedSymbol + r'\b',
    );

    final references = <CodeReference>[];

    for (final document in documents) {
      final lines = document.code
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');

      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final originalLine = lines[lineIndex];

        for (final match in symbolPattern.allMatches(originalLine)) {
          references.add(
            CodeReference(
              fileName: document.fileName,
              line: lineIndex + 1,
              column: match.start + 1,
              lineText: originalLine.trim(),
              isDefinition: definitionPattern.hasMatch(originalLine),
              isStandardAnswer: document.isStandardAnswer,
              stepIndex: document.stepIndex,
              sourceCode: document.isStandardAnswer ? document.code : null,
            ),
          );
        }
      }
    }

    references.sort(
      (
        CodeReference first,
        CodeReference second,
      ) {
        if (first.isDefinition != second.isDefinition) {
          return first.isDefinition ? -1 : 1;
        }

        if (first.isStandardAnswer != second.isStandardAnswer) {
          return first.isStandardAnswer ? 1 : -1;
        }

        final stepResult = first.stepIndex.compareTo(second.stepIndex);

        if (stepResult != 0) {
          return stepResult;
        }

        final fileResult = first.fileName.compareTo(second.fileName);

        if (fileResult != 0) {
          return fileResult;
        }

        final lineResult = first.line.compareTo(second.line);

        if (lineResult != 0) {
          return lineResult;
        }

        return first.column.compareTo(second.column);
      },
    );

    return references;
  }

  Future<CodeReference?> findDefinition(
    String symbol, {
    bool preferStandardAnswer = false,
  }) async {
    final definitions = (await findReferences(symbol))
        .where((reference) => reference.isDefinition)
        .toList();

    if (definitions.isEmpty) {
      return null;
    }

    for (final definition in definitions) {
      if (definition.isStandardAnswer == preferStandardAnswer) {
        return definition;
      }
    }

    return definitions.first;
  }

  /// 只负责打开学生输入区中的引用。
  Future<void> openReference(
    CodeReference reference,
  ) async {
    if (reference.isStandardAnswer) {
      return;
    }

    _captureCode();

    if (reference.stepIndex != currentStepIndex) {
      currentStepIndex = reference.stepIndex;
      _loadStep();
    }

    if (currentFile != reference.fileName) {
      currentFile = reference.fileName;

      final targetCode = _codeForFile(
        reference.fileName,
      );

      fileCodes.putIfAbsent(
        reference.fileName,
        () => targetCode,
      );

      playground.textController.text = targetCode;
      _refreshPreview();
    }

    final lines = playground.textController.text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    if (lines.isEmpty) {
      return;
    }

    final lineIndex = (reference.line - 1).clamp(0, lines.length - 1).toInt();

    final offset =
        (reference.column - 1).clamp(0, lines[lineIndex].length).toInt();

    final position = CodeLinePosition(
      index: lineIndex,
      offset: offset,
    );

    playground.textController.selection = CodeLineSelection.collapsed(
      index: lineIndex,
      offset: offset,
    );

    playground.textController.makePositionCenterIfInvisible(position);

    await _save();
    notifyListeners();
  }

  Future<String?> _loadStandardAnswerCode(
    String assetPath,
  ) async {
    if (_standardAnswerCodeCache.containsKey(assetPath)) {
      return _standardAnswerCodeCache[assetPath];
    }

    try {
      final answer = await answerRepository.load(assetPath);

      final code = answer.isAvailable ? answer.code : null;

      _standardAnswerCodeCache[assetPath] = code;

      return code;
    } catch (_) {
      _standardAnswerCodeCache[assetPath] = null;
      return null;
    }
  }

  int? _stepIndexContainingFile(String file) {
    for (var index = 0; index < lesson.steps.length; index++) {
      final step = lesson.steps[index];

      if (step.currentFile == file ||
          step.relatedFiles.contains(file) ||
          step.standardAnswerAssets.containsKey(file)) {
        return index;
      }
    }

    return null;
  }

  String _codeForFile(String file) {
    final savedCode = fileCodes[file];

    if (savedCode != null) {
      return savedCode;
    }

    for (final step in lesson.steps) {
      if (step.currentFile == file) {
        return lastCode[step.id] ?? step.starterCode;
      }
    }

    return '';
  }

  bool _isValidIdentifier(String value) {
    return RegExp(
      r'^[A-Za-z_$][A-Za-z0-9_$]*$',
    ).hasMatch(value);
  }

  bool _isIdentifierCodeUnit(int codeUnit) {
    final isUppercase = codeUnit >= 65 && codeUnit <= 90;

    final isLowercase = codeUnit >= 97 && codeUnit <= 122;

    final isNumber = codeUnit >= 48 && codeUnit <= 57;

    return isUppercase ||
        isLowercase ||
        isNumber ||
        codeUnit == 95 ||
        codeUnit == 36;
  }

  @override
  void dispose() {
    playground.removeListener(_relay);
    playground.dispose();
    super.dispose();
  }
}

class _ReferenceDocument {
  const _ReferenceDocument({
    required this.fileName,
    required this.code,
    required this.stepIndex,
    required this.isStandardAnswer,
  });

  final String fileName;
  final String code;
  final int stepIndex;
  final bool isStandardAnswer;
}
