abstract final class LessonCatalogLocalization {
  static String normalizeLanguage(String languageCode) {
    return languageCode.toLowerCase().startsWith('en') ? 'en' : 'zh';
  }

  static void materialize(
    Map<String, dynamic> catalog,
    String languageCode,
  ) {
    final normalized = normalizeLanguage(languageCode);
    _applyNode(catalog, normalized);

    final projects = catalog['projects'];
    if (projects is! Iterable) return;

    for (final rawProject in projects) {
      if (rawProject is! Map) continue;
      final project = Map<String, dynamic>.from(rawProject);
      _replace(rawProject, project);
      _applyNode(project, normalized);

      final lessons = project['lessons'];
      if (lessons is! Iterable) continue;
      for (final rawLesson in lessons) {
        if (rawLesson is! Map) continue;
        final lesson = Map<String, dynamic>.from(rawLesson);
        _replace(rawLesson, lesson);
        _applyNode(lesson, normalized);

        final steps = lesson['steps'];
        if (steps is! Iterable) continue;
        for (final rawStep in steps) {
          if (rawStep is! Map) continue;
          final step = Map<String, dynamic>.from(rawStep);
          _replace(rawStep, step);
          _applyNode(step, normalized);
        }
      }
    }
  }

  static void _applyNode(
    Map<String, dynamic> node,
    String languageCode,
  ) {
    final translations = node['translations'];
    if (translations is! Map) return;

    final preferred = translations[languageCode];
    final fallback = translations[languageCode == 'en' ? 'zh' : 'en'];
    final locale = preferred is Map
        ? preferred
        : fallback is Map
            ? fallback
            : null;
    if (locale == null) return;

    for (final entry in locale.entries) {
      node[entry.key.toString()] = entry.value;
    }
  }

  static void _replace(Map raw, Map<String, dynamic> normalized) {
    raw
      ..clear()
      ..addAll(normalized);
  }
}
