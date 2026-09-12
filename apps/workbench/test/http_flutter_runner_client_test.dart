import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/models/run_session.dart';
import 'package:flutter_ui_playground/features/runner/services/http_flutter_runner_client.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_capability.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_change.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP runner creates, syncs and starts a real runner session', () async {
    final requests = <http.Request>[];
    final httpClient = MockClient((request) async {
      requests.add(request);

      if (request.method == 'POST' && request.url.path == '/sessions') {
        return http.Response(
          jsonEncode({
            'session': {
              'id': 'real-1',
              'projectType': 'flutter-serverpod-mini',
              'status': 'ready',
              'createdAt': '2026-09-02T13:00:00.000Z',
              'lastActivityAt': '2026-09-02T13:00:00.000Z',
              'firebaseCapabilities': ['auth', 'firestore'],
              'previewUrl': null,
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'PUT' &&
          request.url.path == '/sessions/real-1/workspace') {
        return http.Response('{}', 200);
      }

      if (request.method == 'POST' &&
          request.url.path == '/sessions/real-1/run') {
        return http.Response('{}', 202);
      }

      return http.Response(
        jsonEncode({'error': 'unexpected request'}),
        500,
      );
    });

    final client = HttpFlutterRunnerClient(
      baseUrl: 'http://runner.test/',
      httpClient: httpClient,
    );
    const capabilities = <FirebaseCapability>{
      FirebaseCapability.auth,
      FirebaseCapability.firestore,
    };

    final session = await client.createSession(
      files: {'lib/main.dart': 'void main() {}'},
      firebaseCapabilities: capabilities,
    );
    expect(session.id, 'real-1');
    expect(session.status, RunnerStatus.ready);
    expect(session.projectType, 'flutter-serverpod-mini');
    expect(session.firebaseCapabilities, capabilities);
    expect(client.isMock, isFalse);

    await client.syncWorkspace(
      sessionId: session.id,
      files: {'lib/main.dart': 'void main() {}'},
      changes: const [
        WorkspaceChange(
          type: WorkspaceChangeType.modified,
          path: 'lib/main.dart',
        ),
      ],
      firebaseCapabilities: capabilities,
    );
    await client.run(session.id);

    expect(
      requests.map((request) => '${request.method} ${request.url.path}'),
      [
        'POST /sessions',
        'PUT /sessions/real-1/workspace',
        'POST /sessions/real-1/run',
      ],
    );

    final createBody = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(createBody['firebaseCapabilities'], ['auth', 'firestore']);

    final syncBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(syncBody['files']['lib/main.dart'], 'void main() {}');
    expect(syncBody['changes'][0]['type'], 'modified');
    expect(syncBody['firebaseCapabilities'], ['auth', 'firestore']);
  });
}
