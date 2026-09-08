import '../controllers/workspace_controller.dart';

class ServerpodWorkspaceService {
  const ServerpodWorkspaceService();

  static const serverRoot = 'serverpod';
  static const serverPackage = '$serverRoot/practice_server';
  static const clientPackage = '$serverRoot/practice_client';
  static const serverPubspecPath = '$serverPackage/pubspec.yaml';
  static const clientPubspecPath = '$clientPackage/pubspec.yaml';
  static const clientLibraryPath = '$clientPackage/lib/practice_client.dart';
  static const generatorConfigPath = '$serverPackage/config/generator.yaml';
  static const developmentConfigPath = '$serverPackage/config/development.yaml';
  static const serverMainPath = '$serverPackage/bin/main.dart';
  static const serverLibraryPath = '$serverPackage/lib/server.dart';
  static const greetingEndpointPath =
      '$serverPackage/lib/src/greeting_endpoint.dart';
  static const apiClientPath = 'lib/serverpod_api.dart';

  bool isEnabled(WorkspaceController workspace) {
    return workspace.entryAt(serverPubspecPath)?.isFile == true &&
        workspace.entryAt(clientPubspecPath)?.isFile == true &&
        workspace.entryAt(generatorConfigPath)?.isFile == true;
  }

  void ensureEnabled(WorkspaceController workspace) {
    if (workspace.entryAt('backend/pubspec.yaml')?.isFile == true) {
      throw StateError(
        '当前 Workspace 已启用 Dart Frog。请新建或重置练习后再启用 Serverpod。',
      );
    }

    final mainSource = workspace.entryAt('lib/main.dart')?.content ?? '';
    final shouldInstallStarter = _looksLikeStarterMain(mainSource);

    for (final path in const [
      serverRoot,
      serverPackage,
      '$serverPackage/bin',
      '$serverPackage/config',
      '$serverPackage/lib',
      '$serverPackage/lib/src',
      clientPackage,
      '$clientPackage/lib',
    ]) {
      _ensureDirectory(workspace, path);
    }

    _ensureFile(workspace, serverPubspecPath, _serverPubspec);
    _ensureFile(workspace, clientPubspecPath, _clientPubspec);
    _ensureFile(workspace, clientLibraryPath, _clientLibrary);
    _ensureFile(workspace, generatorConfigPath, _generatorConfig);
    _ensureFile(workspace, developmentConfigPath, _developmentConfig);
    _ensureFile(workspace, serverMainPath, _serverMain);
    _ensureFile(workspace, serverLibraryPath, _serverLibrary);
    _ensureFile(workspace, greetingEndpointPath, _greetingEndpoint);
    _ensureFile(workspace, apiClientPath, _apiClient);
    _ensureFlutterClientDependency(workspace);

    if (shouldInstallStarter) {
      workspace.updateFileContent('lib/main.dart', _fullStackMain);
    }
  }

  void _ensureDirectory(WorkspaceController workspace, String path) {
    final existing = workspace.entryAt(path);
    if (existing != null) {
      if (!existing.isDirectory) {
        throw StateError('$path already exists and is not a directory.');
      }
      return;
    }

    final separator = path.lastIndexOf('/');
    final parent = separator == -1 ? '' : path.substring(0, separator);
    final name = separator == -1 ? path : path.substring(separator + 1);
    workspace.createDirectory(parent, name);
  }

  void _ensureFile(
    WorkspaceController workspace,
    String path,
    String content,
  ) {
    final existing = workspace.entryAt(path);
    if (existing != null) {
      if (!existing.isFile) {
        throw StateError('$path already exists and is not a file.');
      }
      return;
    }

    final separator = path.lastIndexOf('/');
    final parent = separator == -1 ? '' : path.substring(0, separator);
    final name = separator == -1 ? path : path.substring(separator + 1);
    workspace.createFile(parent, name, content: content);
  }

  void _ensureFlutterClientDependency(WorkspaceController workspace) {
    final entry = workspace.entryAt('pubspec.yaml');
    if (entry == null || !entry.isFile) {
      throw StateError('Flutter pubspec.yaml is missing.');
    }

    final source = entry.content;
    if (RegExp(r'^\s{2}practice_client\s*:', multiLine: true)
        .hasMatch(source)) {
      return;
    }

    const dependencies = 'dependencies:\n';
    if (!source.contains(dependencies)) {
      throw StateError('pubspec.yaml has no dependencies section.');
    }

    workspace.updateFileContent(
      'pubspec.yaml',
      source.replaceFirst(
        dependencies,
        '${dependencies}  practice_client:\n'
        '    path: serverpod/practice_client\n',
      ),
    );
  }

  bool _looksLikeStarterMain(String source) {
    return source.contains('class PracticeExample') &&
        source.contains("'万文社'") &&
        source.contains("'Glyphora'");
  }

  static const _serverPubspec = '''name: practice_server
description: Serverpod Mini backend for the Flutter practice workspace.
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  serverpod: 3.4.13
''';

  static const _clientPubspec = '''name: practice_client
description: Generated Serverpod client for the practice workspace.
publish_to: none

environment:
  sdk: ^3.8.0

dependencies:
  serverpod_client: 3.4.13
''';

  static const _clientLibrary = '''export 'src/protocol/client.dart';
export 'src/protocol/protocol.dart';
''';

  static const _generatorConfig = '''type: server

client_package_path: ../practice_client
''';

  static const _developmentConfig = '''apiServer:
  port: 8080
  publicHost: localhost
  publicPort: 8080
  publicScheme: http

sessionLogs:
  persistentEnabled: false
  consoleEnabled: true
  consoleLogFormat: text
''';

  static const _serverMain = '''import 'package:practice_server/server.dart';

void main(List<String> args) {
  run(args);
}
''';

  static const _serverLibrary = '''import 'package:serverpod/serverpod.dart';

import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';

Future<void> run(List<String> args) async {
  final pod = Serverpod(args, Protocol(), Endpoints());
  await pod.start();
}
''';

  static const _greetingEndpoint = '''import 'package:serverpod/serverpod.dart';

class GreetingEndpoint extends Endpoint {
  Future<String> hello(Session session, String name) async {
    final value = name.trim();
    final displayName = value.isEmpty ? 'Flutter learner' : value;
    return 'Hello \$displayName from Serverpod!';
  }
}
''';

  static const _apiClient =
      '''import 'package:practice_client/practice_client.dart';

const serverpodUrl = String.fromEnvironment('SERVERPOD_URL');

Client? _client;

Client get serverpodClient {
  if (serverpodUrl.isEmpty) {
    throw StateError(
      'SERVERPOD_URL is injected by the real runner when you press Run.',
    );
  }
  final normalized = serverpodUrl.endsWith('/')
      ? serverpodUrl
      : '\$serverpodUrl/';
  return _client ??= Client(normalized);
}

Future<String> loadServerpodGreeting(String name) async {
  Object? lastError;
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      return await serverpodClient.greeting.hello(name);
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }
  throw StateError('Serverpod request failed: \$lastError');
}
''';

  static const _fullStackMain = '''import 'package:flutter/material.dart';

import 'serverpod_api.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ServerpodPractice(),
    ),
  );
}

class ServerpodPractice extends StatefulWidget {
  const ServerpodPractice({super.key});

  @override
  State<ServerpodPractice> createState() => _ServerpodPracticeState();
}

class _ServerpodPracticeState extends State<ServerpodPractice> {
  final nameController = TextEditingController(text: 'Flutter learner');
  String message = 'Press the button to call the generated Serverpod client.';
  bool loading = false;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> callServer() async {
    setState(() => loading = true);
    try {
      final result = await loadServerpodGreeting(nameController.text);
      if (!mounted) return;
      setState(() => message = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'Serverpod error: \$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Serverpod Mini Practice')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
// QUICK_PREVIEW_START
Text(
  'Flutter + Serverpod',
  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
)
// QUICK_PREVIEW_END
                ,
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => callServer(),
                ),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: loading ? null : callServer,
                  icon: loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync),
                  label: const Text('Call generated client'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
''';
}
