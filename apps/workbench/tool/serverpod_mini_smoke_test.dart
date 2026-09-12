import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/services/serverpod_workspace_service.dart';

void main() {
  test(
    'Serverpod Mini generates a typed client and completes a real RPC',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flutter-practice-serverpod-e2e-',
      );
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: '''
class PracticeExample {}
const chineseName = '万文社';
const englishName = 'Glyphora';
''',
      );
      Process? serverProcess;
      final serverLogs = <String>[];

      try {
        const ServerpodWorkspaceService().ensureEnabled(workspace);
        await _materializeWorkspace(root, workspace);

        final serverDirectory = _directory(
          root,
          ServerpodWorkspaceService.serverPackage,
        );
        await _runDart(
          const ['pub', 'get'],
          workingDirectory: serverDirectory.path,
          label: 'server dart pub get',
        );
        await _runDart(
          const [
            'pub',
            'global',
            'run',
            'serverpod_cli:serverpod_cli',
            'generate',
          ],
          workingDirectory: serverDirectory.path,
          label: 'serverpod generate',
        );

        final generatedClientProtocol = _file(
          root,
          '${ServerpodWorkspaceService.clientPackage}/lib/src/protocol/protocol.dart',
        );
        final generatedServerEndpoints = _file(
          root,
          '${ServerpodWorkspaceService.serverPackage}/lib/src/generated/endpoints.dart',
        );
        expect(
          await generatedClientProtocol.exists(),
          isTrue,
          reason: 'serverpod generate must create the client protocol.',
        );
        expect(
          await generatedServerEndpoints.exists(),
          isTrue,
          reason: 'serverpod generate must create the server endpoint registry.',
        );

        final port = await _reservePort();
        serverProcess = await Process.start(
          'dart',
          const ['bin/main.dart', '--mode', 'development'],
          workingDirectory: serverDirectory.path,
          runInShell: Platform.isWindows,
          environment: {
            ...Platform.environment,
            'SERVERPOD_API_SERVER_PORT': '$port',
            'SERVERPOD_API_SERVER_PUBLIC_PORT': '$port',
            'SERVERPOD_API_SERVER_PUBLIC_HOST': '127.0.0.1',
            'SERVERPOD_API_SERVER_PUBLIC_SCHEME': 'http',
          },
        );
        _captureLogs(serverProcess, serverLogs);
        await _waitForPort(port, serverLogs);

        final smokeClientDirectory = _directory(root, 'smoke_client');
        await Directory(
          _nativePath(smokeClientDirectory.path, 'bin'),
        ).create(recursive: true);
        await File(
          _nativePath(smokeClientDirectory.path, 'pubspec.yaml'),
        ).writeAsString('''name: serverpod_mini_smoke_client
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  practice_client:
    path: ../serverpod/practice_client
''');
        await File(
          _nativePath(smokeClientDirectory.path, 'bin/main.dart'),
        ).writeAsString('''import 'dart:io';

import 'package:practice_client/practice_client.dart';

Future<void> main(List<String> args) async {
  final client = Client(args.single);
  final result = await client.greeting.hello('CI');
  const expected = 'Hello CI from Serverpod!';
  if (result != expected) {
    stderr.writeln('Expected: \$expected');
    stderr.writeln('Actual: \$result');
    exitCode = 1;
    return;
  }
  stdout.writeln(result);
}
''');

        await _runDart(
          const ['pub', 'get'],
          workingDirectory: smokeClientDirectory.path,
          label: 'typed client dart pub get',
        );
        final clientResult = await _runDart(
          [
            'run',
            'bin/main.dart',
            'http://127.0.0.1:$port/',
          ],
          workingDirectory: smokeClientDirectory.path,
          label: 'typed Serverpod RPC',
        );

        expect(
          '${clientResult.stdout}',
          contains('Hello CI from Serverpod!'),
        );
      } finally {
        if (serverProcess != null) {
          await _stopProcess(serverProcess);
        }
        workspace.dispose();
        if (await root.exists()) {
          try {
            await root.delete(recursive: true);
          } on FileSystemException {
            // A just-terminated process can briefly keep files open locally.
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _materializeWorkspace(
  Directory root,
  WorkspaceController workspace,
) async {
  final directories = workspace.entries.where((entry) => entry.isDirectory)
      .toList()
    ..sort(
      (a, b) => a.path.split('/').length.compareTo(b.path.split('/').length),
    );
  for (final entry in directories) {
    await _directory(root, entry.path).create(recursive: true);
  }

  for (final entry in workspace.entries.where((entry) => entry.isFile)) {
    final file = _file(root, entry.path);
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.content, flush: true);
  }
}

Future<ProcessResult> _runDart(
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  final result = await Process.run(
    'dart',
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    fail(
      '$label failed with exit code ${result.exitCode}.\n'
      'stdout:\n${result.stdout}\n'
      'stderr:\n${result.stderr}',
    );
  }
  return result;
}

void _captureLogs(Process process, List<String> logs) {
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => logs.add('[stdout] $line'));
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => logs.add('[stderr] $line'));
}

Future<void> _waitForPort(int port, List<String> logs) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      socket.destroy();
      return;
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  fail(
    'Serverpod did not open port $port within 20 seconds.\n'
    '${logs.join('\n')}',
  );
}

Future<int> _reservePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _stopProcess(Process process) async {
  process.kill(ProcessSignal.sigterm);
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill();
    }
  }
}

Directory _directory(Directory root, String relativePath) {
  return Directory(_nativePath(root.path, relativePath));
}

File _file(Directory root, String relativePath) {
  return File(_nativePath(root.path, relativePath));
}

String _nativePath(String root, String relativePath) {
  return <String>[
    root,
    ...relativePath.split('/'),
  ].join(Platform.pathSeparator);
}
