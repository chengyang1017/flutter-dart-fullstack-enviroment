abstract final class CatalogLocalization {
  /// Materializes one language into the legacy root fields used by the current
  /// admin UI. Translation payloads stay attached, so switching/editing can be
  /// added without changing the persisted schema again.
  static void materialize(Map<String, dynamic> catalog, String languageCode) {
    _applyNode(catalog, languageCode);
    final projects = catalog['projects'];
    if (projects is! Iterable) return;

    for (final rawProject in projects) {
      if (rawProject is! Map) continue;
      final project = Map<String, dynamic>.from(rawProject);
      _replace(rawProject, project);
      _applyNode(project, languageCode);

      final lessons = project['lessons'];
      if (lessons is! Iterable) continue;
      for (final rawLesson in lessons) {
        if (rawLesson is! Map) continue;
        final lesson = Map<String, dynamic>.from(rawLesson);
        _replace(rawLesson, lesson);
        _applyNode(lesson, languageCode);

        final steps = lesson['steps'];
        if (steps is! Iterable) continue;
        for (final rawStep in steps) {
          if (rawStep is! Map) continue;
          final step = Map<String, dynamic>.from(rawStep);
          _replace(rawStep, step);
          _applyNode(step, languageCode);
        }
      }
    }
  }

  /// Copies current root presentation fields back into a translation before
  /// saving from the admin UI. Non-presentation fields such as starter code,
  /// requirements and answer assets are never touched.
  static void capture(Map<String, dynamic> catalog, String languageCode) {
    final projects = catalog['projects'];
    if (projects is! Iterable) return;

    for (final rawProject in projects) {
      if (rawProject is! Map) continue;
      final project = Map<String, dynamic>.from(rawProject);
      _replace(rawProject, project);
      _captureNode(project, languageCode, const ['title', 'description']);

      final lessons = project['lessons'];
      if (lessons is! Iterable) continue;
      for (final rawLesson in lessons) {
        if (rawLesson is! Map) continue;
        final lesson = Map<String, dynamic>.from(rawLesson);
        _replace(rawLesson, lesson);
        _captureNode(
          lesson,
          languageCode,
          const [
            'title',
            'description',
            'difficulty',
            'category',
            'tags',
            'prerequisites',
          ],
        );

        final steps = lesson['steps'];
        if (steps is! Iterable) continue;
        for (final rawStep in steps) {
          if (rawStep is! Map) continue;
          final step = Map<String, dynamic>.from(rawStep);
          _replace(rawStep, step);
          _captureNode(
            step,
            languageCode,
            const ['part', 'title', 'instruction', 'explanation', 'hints'],
          );
        }
      }
    }
  }

  static void _applyNode(Map<String, dynamic> node, String languageCode) {
    final translations = node['translations'];
    if (translations is! Map) return;
    final locale = translations[languageCode];
    if (locale is! Map) return;
    for (final entry in locale.entries) {
      node[entry.key.toString()] = entry.value;
    }
  }

  static void _captureNode(
    Map<String, dynamic> node,
    String languageCode,
    List<String> fields,
  ) {
    final translations = node['translations'] is Map
        ? Map<String, dynamic>.from(node['translations'] as Map)
        : <String, dynamic>{};
    final locale = translations[languageCode] is Map
        ? Map<String, dynamic>.from(translations[languageCode] as Map)
        : <String, dynamic>{};
    for (final field in fields) {
      if (node.containsKey(field)) locale[field] = node[field];
    }
    translations[languageCode] = locale;
    node['translations'] = translations;
  }

  static void _replace(Map raw, Map<String, dynamic> normalized) {
    raw
      ..clear()
      ..addAll(normalized);
  }
}
