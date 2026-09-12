import 'lesson_requirement.dart';

enum LessonStepType { ui, model, logic, service, firebase, integration }

enum CheckMode { uiAst, dartAst, unitTest, manualReference }

class LessonStep {
  const LessonStep({
    required this.id,
    required this.title,
    required this.instruction,
    required this.stepType,
    required this.explanation,
    required this.starterCode,
    this.standardAnswerAssets = const {},
    required this.hints,
    required this.requirements,
    required this.relatedFiles,
    required this.checkMode,
    required this.part,
  });
  final String id;
  final String title;
  final String instruction;
  final LessonStepType stepType;
  final String explanation;
  final String starterCode;
  final Map<String, String> standardAnswerAssets;
  final List<String> hints;
  final List<LessonRequirement> requirements;
  final List<String> relatedFiles;
  final CheckMode checkMode;
  final String part;
  String get currentFile => relatedFiles.first;
}
