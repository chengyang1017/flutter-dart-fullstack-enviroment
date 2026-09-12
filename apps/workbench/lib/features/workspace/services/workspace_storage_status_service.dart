import 'dart:convert';

import 'package:http/http.dart' as http;

import 'workspace_cloud_runtime.dart';

class WorkspaceStorageStatus {
  const WorkspaceStorageStatus({
    required this.available,
    this.rootPath,
    this.mountPath,
    this.totalBytes,
    this.usedBytes,
    this.availableBytes,
    this.usagePercent,
    this.reason,
  });

  final bool available;
  final String? rootPath;
  final String? mountPath;
  final int? totalBytes;
  final int? usedBytes;
  final int? availableBytes;
  final double? usagePercent;
  final String? reason;

  factory WorkspaceStorageStatus.fromJson(Map<String, dynamic> json) {
    int? readInt(String key) {
      final value = json[key];
      return value is num ? value.toInt() : null;
    }

    double? readDouble(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : null;
    }

    return WorkspaceStorageStatus(
      available: json['available'] == true,
      rootPath: json['rootPath'] is String ? json['rootPath'] as String : null,
      mountPath:
          json['mountPath'] is String ? json['mountPath'] as String : null,
      totalBytes: readInt('totalBytes'),
      usedBytes: readInt('usedBytes'),
      availableBytes: readInt('availableBytes'),
      usagePercent: readDouble('usagePercent'),
      reason: json['reason'] is String ? json['reason'] as String : null,
    );
  }
}

class WorkspaceStorageStatusService {
  const WorkspaceStorageStatusService();

  Future<WorkspaceStorageStatus> load() async {
    if (!WorkspaceCloudRuntime.enabled) {
      throw StateError('Workspace cloud is not enabled.');
    }

    final configuredApiUrl = WorkspaceCloudRuntime.apiUrl.trim();
    final accessToken = WorkspaceCloudRuntime.accessToken?.trim() ?? '';
    if (configuredApiUrl.isEmpty || accessToken.isEmpty) {
      throw StateError('Workspace cloud connection is not configured.');
    }

    final baseUri = Uri.tryParse(configuredApiUrl);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https')) {
      throw StateError('WORKSPACE_STORAGE_API_URL is invalid.');
    }

    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    final uri = baseUri.replace(
      pathSegments: <String>[...baseSegments, 'storage', 'status'],
      queryParameters: null,
      fragment: null,
    );

    final response = await http.get(
      uri,
      headers: <String, String>{
        'accept': 'application/json',
        'authorization': 'Bearer $accessToken',
      },
    );

    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Storage status response must be an object.');
    }
    final body = Map<String, dynamic>.from(decoded);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body['error'];
      throw StateError(
        message is String && message.isNotEmpty
            ? message
            : 'Storage status request failed (${response.statusCode}).',
      );
    }

    return WorkspaceStorageStatus.fromJson(body);
  }
}
