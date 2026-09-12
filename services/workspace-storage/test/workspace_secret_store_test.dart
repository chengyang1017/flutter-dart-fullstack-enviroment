import 'dart:io';

import 'package:test/test.dart';
import 'package:workspace_storage_server/workspace_storage_server.dart';

void main() {
  late Directory temp;
  late FileWorkspaceSecretStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('workspace-secret-test-');
    store = FileWorkspaceSecretStore(
      temp,
      masterKey: List<int>.generate(32, (index) => index),
      clock: () => DateTime.utc(2026, 9, 3, 1),
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('stores encrypted values and exposes metadata only', () async {
    final metadata = await store.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'GITHUB_TOKEN',
      value: 'super-secret-token',
      contexts: const <String>{'git'},
    );

    expect(metadata['name'], 'GITHUB_TOKEN');
    expect(metadata['contexts'], <String>['git']);
    expect(metadata.containsKey('value'), isFalse);

    final files = await temp.list(recursive: true).where((entity) => entity is File).toList();
    expect(files, hasLength(1));
    final persisted = await (files.single as File).readAsString();
    expect(persisted, isNot(contains('super-secret-token')));
    expect(persisted, contains('aes-gcm-256'));

    final listed = await store.listSecrets(
      userId: 'alice',
      workspaceId: 'workspace-a',
    );
    expect(listed, hasLength(1));
    expect(listed.single.containsKey('value'), isFalse);
  });

  test('trusted execution resolves only an allowed context', () async {
    await store.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'API_KEY',
      value: 'runtime-secret',
      contexts: const <String>{'runner'},
    );

    expect(
      await store.resolveForTrustedExecution(
        userId: 'alice',
        workspaceId: 'workspace-a',
        name: 'API_KEY',
        context: 'runner',
      ),
      'runtime-secret',
    );

    await expectLater(
      store.resolveForTrustedExecution(
        userId: 'alice',
        workspaceId: 'workspace-a',
        name: 'API_KEY',
        context: 'git',
      ),
      throwsStateError,
    );
  });

  test('AAD prevents moving ciphertext between users or workspaces', () async {
    await store.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'API_KEY',
      value: 'bound-secret',
      contexts: const <String>{'runner'},
    );

    final source = await temp
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .single;
    final bobDirectory = Directory('${temp.path}/users/Ym9i/secrets/d29ya3NwYWNlLWE');
    await bobDirectory.create(recursive: true);
    final copied = File('${bobDirectory.path}/QVBJX0tFWQ.json');
    await source.copy(copied.path);

    await expectLater(
      store.resolveForTrustedExecution(
        userId: 'bob',
        workspaceId: 'workspace-a',
        name: 'API_KEY',
        context: 'runner',
      ),
      throwsFormatException,
    );
  });

  test('workspace cleanup removes all associated secret material', () async {
    await store.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-a',
      name: 'A',
      value: 'one',
      contexts: const <String>{'git'},
    );
    await store.putSecret(
      userId: 'alice',
      workspaceId: 'workspace-b',
      name: 'B',
      value: 'two',
      contexts: const <String>{'deploy'},
    );

    await store.retainWorkspaces(
      userId: 'alice',
      workspaceIds: const <String>{'workspace-b'},
    );

    expect(
      await store.listSecrets(userId: 'alice', workspaceId: 'workspace-a'),
      isEmpty,
    );
    expect(
      await store.listSecrets(userId: 'alice', workspaceId: 'workspace-b'),
      hasLength(1),
    );
  });
}
