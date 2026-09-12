import 'package:flutter/material.dart';

import 'lesson.dart';

class LessonProject {
  const LessonProject({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.lessons,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final List<Lesson> lessons;

  int get availableLessonCount {
    return lessons.where((lesson) => !lesson.comingSoon).length;
  }

  int get totalStepCount {
    return lessons.fold(
      0,
      (total, lesson) => total + lesson.steps.length,
    );
  }
}
