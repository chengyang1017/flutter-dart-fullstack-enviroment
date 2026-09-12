import 'dart:convert';
import 'dart:io';

import 'package:flutter_practice_runner_server/src/execution/execution_backend.dart';
import 'package:flutter_practice_runner_server/src/runner_authenticator.dart';
import 'package:flutter_practice_runner_server/src/runner_server.dart';
import 'package:flutter_practice_runner_server/src/runner_session.dart';
import 'package:flutter_practice_runner_server/src/session_manager.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late HttpServer rawServer;
  late HttpClient client;
  late Uri baseUri;
  late SessionManager manager;
  late _FakeExecutionBackend backend;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('runner-auth-test-');
    backend = _FakeExecutionBackend();

    manager = SessionManager(
      rootDirectory: temp,
      executionBackend: backend,
      previewUrlTemplate: 'http://localhost:{port}',
      backendUrlTemplate: 'http://localhost:{port}',
    );
    final handler = RunnerServer(
      manager: manager,
      authenticator: const StaticBearerRunnerAuthenticator(
        <String, String>{
          'alice-token': 'alice',
          'bob-token': 'bob',
        },
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
    await manager.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('sessions require authentication and are scoped to their owner', () async {
    final unauthenticated = await _request(client, baseUri, 'POST', 'sessions');
    expect(unauthenticated.statusCode, HttpStatus.unauthorized);

    final created = await _request(
      client,
      baseUri,
      'POST',
      'sessions',
      token: 'alice-token',
      body: '{"files":{"lib/main.dart":"void main() {}"}}',
    );
    expect(created.statusCode, HttpStatus.created);
    final sessionId = RegExp(r'"id":"([^"]+)"')
        .firstMatch(created.body)!
        .group(1)!;

    final aliceRead = await _request(
      client,
      baseUri,
      'GET',
      'sessions/$sessionId',
      token: 'alice-token',
    );
    expect(aliceRead.statusCode, HttpStatus.ok);

    final bobRead = await _request(
      client,
      baseUri,
      'GET',
      'sessions/$sessionId',
      token: 'bob-token',
    );
    expect(bobRead.statusCode, HttpStatus.notFound);
  });

    test('session accepts Flutter project name and selected platforms', () async {
    final created = await _request(
      client,
      baseUri,
      'POST',
      'sessions',
      token: 'alice-token',
      body: jsonEncode(
        <String, Object?>{
          'files': <String, String>{},
          'projectName': 'my_app',
          'platforms': <String>[
            'android',
            'web',
            'windows',
          ],
        },
      ),
    );

    expect(
      created.statusCode,
      HttpStatus.created,
    );

    expect(
      backend.lastFlutterArguments,
      <String>[
        'create',
        '--no-pub',
        '--platforms=android,web,windows',
        '--project-name=my_app',
        '.',
      ],
    );
  });

    test(
    'created Flutter project returns generated workspace tree',
    () async {
      final created = await _request(
        client,
        baseUri,
        'POST',
        'sessions',
        token: 'alice-token',
        body: jsonEncode(
          <String, Object?>{
            'files': <String, String>{},
            'projectName': 'my_app',
            'platforms': <String>[
              'android',
              'web',
              'windows',
            ],
            'includeWorkspace': true,
          },
        ),
      );

      expect(
        created.statusCode,
        HttpStatus.created,
      );

      final body =
          jsonDecode(created.body)
              as Map<String, dynamic>;

      final workspace =
          body['workspace']
              as Map<String, dynamic>;

      final directories =
          (workspace['directories']
                  as List<dynamic>)
              .cast<String>();

      final files =
          Map<String, dynamic>.from(
        workspace['files'] as Map,
      );

      expect(
        directories,
        containsAll(
          <String>[
            'android',
            'web',
            'windows',
            'lib',
            'test',
          ],
        ),
      );

      expect(
        files,
        containsPair(
          'lib/main.dart',
          'void main() {}\n',
        ),
      );

      expect(
        files.containsKey(
          'pubspec.yaml',
        ),
        isTrue,
      );

      expect(
        files.containsKey(
          'test/widget_test.dart',
        ),
        isTrue,
      );
    },
  );

  test('binary Workspace envelope is restored to exact file bytes', () async {
    final logoBytes = <int>[0, 137, 80, 78, 71, 13, 10, 26, 10, 255, 1];
    final created = await _request(
      client,
      baseUri,
      'POST',
      'sessions',
      token: 'alice-token',
      body: jsonEncode(<String, Object?>{
        'files': <String, String>{
          'lib/main.dart': 'void main() {}\n',
          'assets/logo.png':
              '\u0000workspace-base64:${base64Encode(logoBytes)}',
        },
      }),
    );

    expect(created.statusCode, HttpStatus.created);
    final body = jsonDecode(created.body) as Map<String, dynamic>;
    final session = body['session'] as Map<String, dynamic>;
    final sessionId = session['id'] as String;
    final asset = File(
      '${temp.path}${Platform.pathSeparator}$sessionId'
      '${Platform.pathSeparator}assets${Platform.pathSeparator}logo.png',
    );
    expect(await asset.readAsBytes(), orderedEquals(logoBytes));
  });

  test('auth token mapping validates configuration', () {
    final auth = StaticBearerRunnerAuthenticator.fromJson(
      '{"runner-token":"user-1"}',
    );
    expect(auth.tokenToUserId['runner-token'], 'user-1');
    expect(
      () => StaticBearerRunnerAuthenticator.fromJson('{}'),
      throwsFormatException,
    );
  });
}

Future<_Response> _request(
  HttpClient client,
  Uri baseUri,
  String method,
  String path, {
  String? token,
  String? body,
}) async {
  final request = await client.openUrl(method, baseUri.resolve(path));
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(body);
  }
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, text);
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _FakeExecutionBackend implements RunnerExecutionBackend {
  List<String>? lastFlutterArguments;

  @override
  String get name => 'fake';

  @override
  Future<void> prepareSession(RunnerSession session) async {}

  @override
  Future<int> runFlutterCommand(
    RunnerSession session,
    List<String> arguments,
  ) async {
    lastFlutterArguments = List<String>.of(arguments);

    if (arguments.isNotEmpty &&
        arguments.first == 'create') {
      final libDirectory = Directory(
        '${session.directory.path}'
        '${Platform.pathSeparator}lib',
      );

      final testDirectory = Directory(
        '${session.directory.path}'
        '${Platform.pathSeparator}test',
      );

      await libDirectory.create(
        recursive: true,
      );

      await testDirectory.create(
        recursive: true,
      );

      await File(
        '${libDirectory.path}'
        '${Platform.pathSeparator}main.dart',
      ).writeAsString(
        'void main() {}\n',
      );

      await File(
        '${session.directory.path}'
        '${Platform.pathSeparator}pubspec.yaml',
      ).writeAsString(
        'name: my_app\n'
        'environment:\n'
        '  sdk: ^3.0.0\n'
        'dependencies:\n'
        '  flutter:\n'
        '    sdk: flutter\n',
      );

      await File(
        '${testDirectory.path}'
        '${Platform.pathSeparator}widget_test.dart',
      ).writeAsString(
        'void main() {}\n',
      );

      final platformArgument =
          arguments.firstWhere(
        (argument) =>
            argument.startsWith(
          '--platforms=',
        ),
        orElse: () => '',
      );

      if (platformArgument.isNotEmpty) {
        final platforms =
            platformArgument
                .substring(
                  '--platforms='.length,
                )
                .split(',');

        for (final platform in platforms) {
          await Directory(
            '${session.directory.path}'
            '${Platform.pathSeparator}$platform',
          ).create(
            recursive: true,
          );
        }
      }
    }

    return 0;
  }

  @override
  Future<void> pullWorkspace(
    RunnerSession session,
  ) async {}

  @override
  Future<void> syncWorkspace(
    RunnerSession session, {
    required Set<String> removedPaths,
  }) async {}

  @override
  Future<int> runDartCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'backend',
  }) async => 0;

  @override
  Future<int> runServerpodCommand(
    RunnerSession session,
    List<String> arguments, {
    String workingDirectory = 'serverpod/practice_server',
  }) async => 0;

  @override
  Future<RunnerProcessLaunch> startFlutterWeb(
    RunnerSession session, {
    Map<String, String> dartDefines = const <String, String>{},
  }) => throw UnimplementedError();

  @override
  Future<RunnerProcessLaunch> startDartFrog(RunnerSession session) =>
      throw UnimplementedError();

  @override
  Future<RunnerProcessLaunch> startServerpod(
    RunnerSession session, {
    String workingDirectory = 'serverpod/practice_server',
  }) => throw UnimplementedError();

  @override
  Future<void> forceStop(RunnerSession session, Process process) async {}

  @override
  Future<void> disposeSession(RunnerSession session) async {}
}