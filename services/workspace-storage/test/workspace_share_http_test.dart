import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late HttpServer rawServer;
  late HttpClient client;
  late Uri baseUri;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-share-http-test-');
    final handler = WorkspaceStorageHttpServer(
      store: FileWorkspaceStore(temp),
      secretStore: FileWorkspaceSecretStore(
        temp,
        masterKey: List<int>.generate(32, (index) => index),
      ),
      authenticator: const StaticBearerWorkspaceAuthenticator(
        <String, String>{'alice-token': 'alice'},
      ),
    );
    rawServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    rawServer.listen(handler.handle);
    client = HttpClient();
    baseUri = Uri.parse('http://127.0.0.1:${rawServer.port}/');
  });

  tearDown(() async {
    client.close(force: true);
    await rawServer.close(force: true);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('share is public, immutable, traversable, and revocable', () async {
    final createdWorkspace = await _jsonRequest(
      client,
      baseUri,
      'POST',
      'workspaces',
      token: 'alice-token',
      body: <String, dynamic>{
        'project': _project('workspace-a'),
        'snapshot': _snapshot('v1'),
      },
    );
    expect(createdWorkspace.statusCode, HttpStatus.created);
    expect(createdWorkspace.json['revision'], 'r1');

    final createdShare = await _jsonRequest(
      client,
      baseUri,
      'POST',
      'workspaces/workspace-a/shares',
      token: 'alice-token',
    );
    expect(createdShare.statusCode, HttpStatus.created);
    final token = createdShare.json['token'] as String;
    expect(token, isNotEmpty);
    expect(createdShare.json['revision'], 'r1');
    expect(createdShare.json['sharePath'], '/shares/$token');

    final listed = await _jsonRequest(
      client,
      baseUri,
      'GET',
      'workspaces/workspace-a/shares',
      token: 'alice-token',
    );
    expect(listed.statusCode, HttpStatus.ok);
    expect(listed.json['shares'], hasLength(1));

    final updatedWorkspace = await _jsonRequest(
      client,
      baseUri,
      'PUT',
      'workspaces/workspace-a',
      token: 'alice-token',
      body: <String, dynamic>{
        'project': _project('workspace-a'),
        'snapshot': _snapshot('v2'),
        'expectedRevision': 'r1',
      },
    );
    expect(updatedWorkspace.statusCode, HttpStatus.ok);
    expect(updatedWorkspace.json['revision'], 'r2');

    final metadata = await _jsonRequest(
      client,
      baseUri,
      'GET',
      'shares/$token',
    );
    expect(metadata.statusCode, HttpStatus.ok);
    expect(metadata.json['apiVersion'], 1);
    expect(metadata.json['kind'], 'workspace-share');
    expect(metadata.json['revision'], 'r1');
    expect((metadata.json['project'] as Map)['name'], 'workspace-a');

    final tree = await _jsonRequest(
      client,
      baseUri,
      'GET',
      'shares/$token/tree',
    );
    expect(tree.statusCode, HttpStatus.ok);
    final entries = tree.json['tree'] as List;
    expect(
      entries.any(
        (entry) =>
            entry is Map &&
            entry['path'] == 'lib/main.dart' &&
            entry['type'] == 'blob' &&
            entry['size'] is int &&
            entry['sha256'] is String,
      ),
      isTrue,
    );

    final raw = await _textRequest(
      client,
      baseUri,
      'GET',
      'shares/$token/raw/lib/main.dart',
    );
    expect(raw.statusCode, HttpStatus.ok);
    expect(raw.text, contains("print('v1')"));
    expect(raw.text, isNot(contains("print('v2')")));

    final revoked = await _jsonRequest(
      client,
      baseUri,
      'DELETE',
      'workspaces/workspace-a/shares/$token',
      token: 'alice-token',
    );
    expect(revoked.statusCode, HttpStatus.noContent);

    final missing = await _jsonRequest(
      client,
      baseUri,
      'GET',
      'shares/$token',
    );
    expect(missing.statusCode, HttpStatus.notFound);
  });
}

Future<_JsonResponse> _jsonRequest(
  HttpClient client,
  Uri baseUri,
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final request = await client.openUrl(method, baseUri.resolve(path));
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  final decoded = text.trim().isEmpty ? <String, dynamic>{} : jsonDecode(text);
  return _JsonResponse(
    response.statusCode,
    decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{},
  );
}

Future<_TextResponse> _textRequest(
  HttpClient client,
  Uri baseUri,
  String method,
  String path,
) async {
  final request = await client.openUrl(method, baseUri.resolve(path));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return _TextResponse(response.statusCode, text);
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.json);

  final int statusCode;
  final Map<String, dynamic> json;
}

class _TextResponse {
  const _TextResponse(this.statusCode, this.text);

  final int statusCode;
  final String text;
}

Map<String, dynamic> _project(String id) => <String, dynamic>{
      'id': id,
      'name': id,
      'slug': id,
      'storageKey': 'workspace:$id',
      'kind': 'practice',
      'lifecycle': 'saved',
      'createdAt': '2026-09-09T00:00:00.000Z',
      'updatedAt': '2026-09-09T00:00:00.000Z',
      'flutterPlatforms': <String>['web'],
    };

Map<String, dynamic> _snapshot(String version) => <String, dynamic>{
      'formatVersion': 3,
      'entries': <Object>[
        <String, dynamic>{
          'id': 'dir-lib',
          'path': 'lib',
          'type': 'directory',
          'content': '',
        },
        <String, dynamic>{
          'id': 'file-main',
          'path': 'lib/main.dart',
          'type': 'file',
          'content': "void main() { print('$version'); }\n",
          'encoding': 'utf8',
        },
        <String, dynamic>{
          'id': 'file-pubspec',
          'path': 'pubspec.yaml',
          'type': 'file',
          'content': 'name: workspace_a\n',
          'encoding': 'utf8',
        },
      ],
      'baseEntries': <Object>[],
      'openFiles': <Object>['lib/main.dart'],
      'activePath': 'lib/main.dart',
      'nextId': 4,
      'savedAt': '2026-09-09T00:00:00.000Z',
      'expandedDirectoryIds': <Object>['dir-lib'],
      'editorStates': <String, Object?>{},
    };
