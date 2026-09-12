import 'lesson_step.dart';

enum LessonVersion {
  beginner,
  intermediate,
  advancedImages,
  advancedTransaction
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.category,
    required this.tags,
    required this.estimatedMinutes,
    this.prerequisites = const [],
    this.comingSoon = false,
    this.version = LessonVersion.beginner,
    required this.steps,
  });
  final String id;
  final String title;
  final String description;
  final String difficulty;
  final String category;
  final List<String> tags;
  final int estimatedMinutes;
  final List<String> prerequisites;
  final bool comingSoon;
  final LessonVersion version;
  final List<LessonStep> steps;
}
