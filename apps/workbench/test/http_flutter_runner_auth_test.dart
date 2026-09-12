import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/services/http_flutter_runner_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP runner sends bearer auth when configured', () async {
    late http.Request captured;
    final httpClient = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'session': <String, dynamic>{
            'id': 'owned-1',
            'projectType': 'flutter',
            'status': 'ready',
            'createdAt': '2026-09-03T00:00:00.000Z',
            'lastActivityAt': '2026-09-03T00:00:00.000Z',
            'firebaseCapabilities': <String>[],
            'previewUrl': null,
            'backendUrl': null,
          },
        }),
        201,
      );
    });

    final client = HttpFlutterRunnerClient(
      baseUrl: 'https://runner.example/',
      accessToken: 'runner-access-token',
      httpClient: httpClient,
    );

    await client.createSession(
      files: const <String, String>{'lib/main.dart': 'void main() {}'},
    );

    expect(captured.headers['authorization'], 'Bearer runner-access-token');
  });
}
