import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../workspace/services/workspace_cloud_runtime.dart';
import '../models/lesson_project.dart';
import 'lesson_catalog.dart';
import 'lesson_catalog_codec.dart';

/// Cloud-backed lesson catalog with a built-in bootstrap fallback.
///
/// The existing Dart lesson catalog is intentionally kept as a migration seed.
/// Once an administrator account opens the updated app against an empty
/// Workspace backend, the built-in catalog is uploaded once. Subsequent loads
/// come from `/content/lessons`, so the Jaspr admin app becomes the source of
/// truth without making existing local/offline lesson mode unusable.
class LessonCatalogRepository {
  LessonCatalogRepository({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<List<LessonProject>> loadProjects() async {
    final configuredUrl = WorkspaceCloudRuntime.apiUrl.trim();
    if (configuredUrl.isEmpty) return LessonCatalog.projects;

    final baseUri = Uri.tryParse(configuredUrl);
    if (baseUri == null || !baseUri.hasScheme) {
      return LessonCatalog.projects;
    }

    try {
      var response = await _client
          .get(baseUri.resolve('/content/lessons'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        await _tryBootstrap(baseUri);
        response = await _client
            .get(baseUri.resolve('/content/lessons'))
            .timeout(const Duration(seconds: 8));
      }

      if (response.statusCode != 200) return LessonCatalog.projects;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return LessonCatalog.projects;
      return LessonCatalogCodec.decodeProjects(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return LessonCatalog.projects;
    }
  }

  Future<void> _tryBootstrap(Uri baseUri) async {
    final accessToken = WorkspaceCloudRuntime.accessToken?.trim() ?? '';
    if (accessToken.isEmpty) return;

    try {
      await _client
          .post(
            baseUri.resolve('/admin/lessons/bootstrap'),
            headers: <String, String>{
              'authorization': 'Bearer $accessToken',
              'content-type': 'application/json',
            },
            body: jsonEncode(
              LessonCatalogCodec.encodeProjects(LessonCatalog.projects),
            ),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Non-admin and offline clients simply keep using the built-in seed.
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
