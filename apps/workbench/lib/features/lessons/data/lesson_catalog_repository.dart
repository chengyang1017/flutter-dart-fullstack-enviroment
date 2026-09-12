import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../workspace/services/workspace_cloud_runtime.dart';
import '../models/lesson.dart';
import '../models/lesson_project.dart';
import 'lesson_catalog_codec.dart';
import 'lesson_catalog_localization.dart';

class LessonCatalogException implements Exception {
  const LessonCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Remote-only lesson catalog.
///
/// Lesson content is owned by the Workspace backend and managed through the
/// Jaspr admin console. The Flutter client intentionally contains no built-in
/// production lesson catalog and never bootstraps lesson content itself.
class LessonCatalogRepository {
  LessonCatalogRepository({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<List<LessonProject>> loadProjects({
    String languageCode = 'zh',
  }) async {
    final normalizedLanguage =
        LessonCatalogLocalization.normalizeLanguage(languageCode);
    final configuredUrl = WorkspaceCloudRuntime.apiUrl.trim();
    if (configuredUrl.isEmpty) {
      throw const LessonCatalogException(
        'Workspace lesson service is not configured.',
      );
    }

    final baseUri = Uri.tryParse(configuredUrl);
    if (baseUri == null || !baseUri.hasScheme) {
      throw const LessonCatalogException(
        'Workspace lesson service URL is invalid.',
      );
    }

    try {
      final response = await _client
          .get(baseUri.resolve('/content/lessons'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        return const <LessonProject>[];
      }
      if (response.statusCode != 200) {
        throw LessonCatalogException(
          'Lesson service returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const LessonCatalogException(
          'Lesson service returned an invalid catalog.',
        );
      }

      final catalog = Map<String, dynamic>.from(decoded);
      LessonCatalogLocalization.materialize(catalog, normalizedLanguage);
      return LessonCatalogCodec.decodeProjects(catalog);
    } on LessonCatalogException {
      rethrow;
    } catch (error) {
      throw LessonCatalogException(
        'Unable to load lessons from Workspace: $error',
      );
    }
  }

  Future<Lesson?> loadLesson(
    String lessonId, {
    String languageCode = 'zh',
  }) async {
    final projects = await loadProjects(languageCode: languageCode);
    for (final project in projects) {
      for (final lesson in project.lessons) {
        if (lesson.id == lessonId) return lesson;
      }
    }
    return null;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
