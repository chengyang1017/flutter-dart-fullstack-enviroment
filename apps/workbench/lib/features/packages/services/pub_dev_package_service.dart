import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/package_models.dart';

class PubDevPackageService {
  PubDevPackageService({http.Client? client}) : _client = client ?? http.Client();

  static List<String>? _cachedPackageNames;
  final http.Client _client;

  Future<List<String>> search(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const <String>[];

    final names = await _packageNames();
    final prefix = <String>[];
    final contains = <String>[];

    for (final name in names) {
      final lower = name.toLowerCase();
      if (lower.startsWith(normalized)) {
        prefix.add(name);
      } else if (lower.contains(normalized)) {
        contains.add(name);
      }
    }

    prefix.sort((a, b) {
      if (a.toLowerCase() == normalized) return -1;
      if (b.toLowerCase() == normalized) return 1;
      return a.length.compareTo(b.length);
    });
    contains.sort((a, b) => a.length.compareTo(b.length));

    final result = <String>[];
    if (RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
      result.add(normalized);
    }
    for (final name in <String>[...prefix, ...contains]) {
      if (!result.contains(name)) result.add(name);
      if (result.length >= 40) break;
    }
    return result;
  }

  Future<PubDevPackageInfo> packageInfo(String packageName) async {
    final response = await _client.get(
      Uri.parse(
        'https://pub.dev/api/packages/${Uri.encodeComponent(packageName)}',
      ),
      headers: const <String, String>{'accept': 'application/json'},
    );
    _requireOk(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('pub.dev package response is invalid.');
    }

    final latest = decoded['latest'];
    if (latest is! Map || latest['version'] is! String) {
      throw const FormatException('pub.dev latest version is missing.');
    }

    final latestVersion = latest['version'] as String;
    final versions = <String>[];
    final rawVersions = decoded['versions'];
    if (rawVersions is List) {
      for (final raw in rawVersions.reversed) {
        if (raw is Map && raw['version'] is String) {
          final version = raw['version'] as String;
          if (!versions.contains(version)) versions.add(version);
        }
      }
    }

    final latestPubspec = latest['pubspec'];
    final description = latestPubspec is Map &&
            latestPubspec['description'] is String
        ? latestPubspec['description'] as String
        : '';

    return PubDevPackageInfo(
      name: packageName,
      latestVersion: latestVersion,
      versions: versions,
      description: description,
    );
  }

  Future<List<String>> _packageNames() async {
    final cached = _cachedPackageNames;
    if (cached != null) return cached;

    final response = await _client.get(
      Uri.parse('https://pub.dev/api/package-name-completion-data'),
      headers: const <String, String>{'accept': 'application/json'},
    );
    _requireOk(response);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['packages'] is! List) {
      throw const FormatException('pub.dev package list format is invalid.');
    }

    final names = (decoded['packages'] as List)
        .whereType<String>()
        .toList(growable: false);
    _cachedPackageNames = names;
    return names;
  }

  void _requireOk(http.Response response) {
    if (response.statusCode != 200) {
      throw StateError('pub.dev returned HTTP ${response.statusCode}.');
    }
  }

  void close() => _client.close();
}
