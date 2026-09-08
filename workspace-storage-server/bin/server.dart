import 'dart:async';
import 'dart:io';

import 'package:workspace_storage_server/workspace_storage_server.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final port = int.tryParse(environment['PORT'] ?? '') ?? 8090;
  final host = environment['HOST'] ?? '0.0.0.0';
  final storageRoot = environment['WORKSPACE_STORAGE_ROOT'] ?? '.workspace-storage';
  final temporaryTtlHours =
      int.tryParse(environment['TEMPORARY_WORKSPACE_TTL_HOURS'] ?? '') ?? 168;
  final sessionTtlDays =
      int.tryParse(environment['WORKSPACE_SESSION_TTL_DAYS'] ?? '') ?? 30;

  if (temporaryTtlHours <= 0) {
    stderr.writeln('TEMPORARY_WORKSPACE_TTL_HOURS must be greater than zero.');
    exitCode = 64;
    return;
  }
  if (sessionTtlDays <= 0) {
    stderr.writeln('WORKSPACE_SESSION_TTL_DAYS must be greater than zero.');
    exitCode = 64;
    return;
  }

  final secretMasterKey = environment['WORKSPACE_SECRET_MASTER_KEY'];
  if (secretMasterKey == null || secretMasterKey.trim().isEmpty) {
    stderr.writeln(
      'WORKSPACE_SECRET_MASTER_KEY is required and must be a base64url-encoded '
      '32-byte key.',
    );
    exitCode = 64;
    return;
  }

  late final List<int> decodedSecretMasterKey;
  try {
    decodedSecretMasterKey = FileWorkspaceSecretStore.decodeMasterKey(
      secretMasterKey,
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }

  final root = Directory(storageRoot);
  final accounts = FileWorkspaceAccountStore(
    root,
    sessionTtl: Duration(days: sessionTtlDays),
  );

  final authenticators = <WorkspaceAuthenticator>[accounts];
  final authTokens = environment['WORKSPACE_AUTH_TOKENS'];
  if (authTokens != null && authTokens.trim().isNotEmpty) {
    try {
      authenticators.insert(
        0,
        StaticBearerWorkspaceAuthenticator.fromJson(authTokens),
      );
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      exitCode = 64;
      return;
    }
  }

  final authenticator = CompositeWorkspaceAuthenticator(authenticators);
  final allowedOrigin = environment['ALLOWED_ORIGIN'] ?? '*';
  final workspaceHandler = WorkspaceStorageHttpServer(
    store: FileWorkspaceStore(
      root,
      temporaryWorkspaceTtl: Duration(hours: temporaryTtlHours),
    ),
    secretStore: FileWorkspaceSecretStore(
      root,
      masterKey: decodedSecretMasterKey,
    ),
    authenticator: authenticator,
    allowedOrigin: allowedOrigin,
  );
  final handler = WorkspaceAuthHttpHandler(
    accounts: accounts,
    workspaceHandler: workspaceHandler,
    allowedOrigin: allowedOrigin,
  );

  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'Workspace storage listening on http://${server.address.address}:${server.port}',
  );
  stdout.writeln('Storage root: ${root.absolute.path}');
  stdout.writeln('Temporary Workspace TTL: $temporaryTtlHours hours');
  stdout.writeln('Workspace account sessions: $sessionTtlDays days');
  stdout.writeln('Workspace password hashing: PBKDF2-HMAC-SHA256');
  stdout.writeln('Workspace secret vault: AES-GCM-256 enabled');
  if (authTokens != null && authTokens.trim().isNotEmpty) {
    stdout.writeln('Static development bearer identities: enabled');
  }

  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Received $signal; shutting down Workspace storage.');
    await server.close(force: true);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(shutdown));
  }
  subscriptions.add(ProcessSignal.sigint.watch().listen(shutdown));

  await for (final request in server) {
    unawaited(handler.handle(request));
  }
}
