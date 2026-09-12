import 'lesson_requirement.dart';

class RequirementCheckResult {
  const RequirementCheckResult(
      {required this.requirement, required this.passed});
  final LessonRequirement requirement;
  final bool passed;
}

class LessonCheckResult {
  const LessonCheckResult({required this.results, this.parseError});
  final List<RequirementCheckResult> results;
  final String? parseError;
  bool get passed =>
      parseError == null && results.every((result) => result.passed);
}
