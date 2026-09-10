import 'dart:convert';
import 'dart:io';

abstract interface class RunnerAuthenticator {
  Future<String?> authenticate(HttpRequest request);
}

class StaticBearerRunnerAuthenticator implements RunnerAuthenticator {
  const StaticBearerRunnerAuthenticator(this.tokenToUserId);

  final Map<String, String> tokenToUserId;

  factory StaticBearerRunnerAuthenticator.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'RUNNER_AUTH_TOKENS must be a JSON object mapping token to user id.',
      );
    }

    final result = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          entry.value is! String ||
          (entry.value as String).isEmpty) {
        throw const FormatException(
          'RUNNER_AUTH_TOKENS keys and values must be non-empty strings.',
        );
      }
      result[entry.key as String] = entry.value as String;
    }
    if (result.isEmpty) {
      throw const FormatException('RUNNER_AUTH_TOKENS cannot be empty.');
    }
    return StaticBearerRunnerAuthenticator(Map.unmodifiable(result));
  }

  @override
  Future<String?> authenticate(HttpRequest request) async {
    final token = _readBearerToken(request);
    if (token == null) return null;
    return tokenToUserId[token];
  }
}

class WorkspaceAccountRunnerAuthenticator implements RunnerAuthenticator {
  WorkspaceAccountRunnerAuthenticator({
    required Uri baseUri,
    this.cacheTtl = const Duration(seconds: 15),
    HttpClient? httpClient,
  })  : _meUri = _buildMeUri(baseUri),
        _httpClient = httpClient ?? HttpClient();

  static const int _maxCacheEntries = 512;

  final Uri _meUri;
  final Duration cacheTtl;
  final HttpClient _httpClient;
  final Map<String, _CachedWorkspaceIdentity> _cache =
      <String, _CachedWorkspaceIdentity>{};

  @override
  Future<String?> authenticate(HttpRequest request) async {
    final token = _readBearerToken(request);
    if (token == null) return null;

    final now = DateTime.now().toUtc();
    final cached = _cache[token];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      return cached.userId;
    }
    if (cached != null) {
      _cache.remove(token);
    }

    try {
      final validation =
          await _httpClient.getUrl(_meUri).timeout(const Duration(seconds: 5));
      validation.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      );
      validation.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.mimeType,
      );

      final response = await validation.close().timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final source = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;

      final rawUserId = decoded['userId'];
      if (rawUserId is! String || rawUserId.trim().isEmpty) {
        return null;
      }

      final userId = rawUserId.trim();
      _remember(
        token,
        userId,
        now.add(cacheTtl),
      );
      return userId;
    } catch (_) {
      return null;
    }
  }

  void close() {
    _httpClient.close(force: true);
    _cache.clear();
  }

  void _remember(
    String token,
    String userId,
    DateTime expiresAt,
  ) {
    if (cacheTtl <= Duration.zero) return;

    final now = DateTime.now().toUtc();
    _cache.removeWhere((_, value) => !value.expiresAt.isAfter(now));

    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }

    _cache[token] = _CachedWorkspaceIdentity(
      userId: userId,
      expiresAt: expiresAt,
    );
  }

  static Uri _buildMeUri(Uri baseUri) {
    if (!baseUri.hasScheme ||
        (baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty) {
      throw FormatException(
        'WORKSPACE_STORAGE_API_URL must be an absolute http/https URL: '
        '$baseUri',
      );
    }

    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    return baseUri.replace(
      pathSegments: <String>[
        ...baseSegments,
        'me',
      ],
      queryParameters: null,
      fragment: null,
    );
  }
}

class _CachedWorkspaceIdentity {
  const _CachedWorkspaceIdentity({
    required this.userId,
    required this.expiresAt,
  });

  final String userId;
  final DateTime expiresAt;
}

String? _readBearerToken(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null || !header.startsWith('Bearer ')) return null;

  final token = header.substring('Bearer '.length).trim();
  return token.isEmpty ? null : token;
}
