import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_export_service.dart';
import 'package:flutter_ui_playground/features/runner/services/workspace_runner_source_provider.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';

void main() {
  test('binary Workspace files survive snapshot, Runner transport and export', () async {
    final logoBytes = <int>[0, 137, 80, 78, 71, 13, 10, 26, 10, 255, 1, 2];
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}\n',
    );
    addTearDown(workspace.dispose);

    final initial = workspace.createSnapshot();
    final binary = WorkspaceEntry.binary(
      id: 'file-logo',
      path: 'assets/logo.png',
      bytes: logoBytes,
    );
    final snapshot = WorkspaceSnapshot(
      entries: <WorkspaceEntry>[...initial.entries, binary],
      baseEntries: <WorkspaceEntry>[...initial.baseEntries, binary],
      openFiles: initial.openFiles,
      activePath: initial.activePath,
      nextId: initial.nextId + 1,
      savedAt: DateTime.utc(2026, 9, 3),
      expandedDirectoryIds: initial.expandedDirectoryIds,
      editorStates: initial.editorStates,
    );

    final decoded = WorkspaceSnapshot.fromJson(snapshot.toJson());
    expect(decoded.formatVersion, WorkspaceSnapshot.currentFormatVersion);
    final decodedAsset = decoded.entries.singleWhere(
      (entry) => entry.path == 'assets/logo.png',
    );
    expect(decodedAsset.isBinary, isTrue);
    expect(decodedAsset.bytes, orderedEquals(logoBytes));

    workspace.restoreSnapshot(decoded);
    final source = await LocalWorkspaceRunnerSourceProvider(workspace).prepare();
    final runnerPayload = source.files['assets/logo.png'];
    expect(runnerPayload, isNotNull);
    expect(
      runnerPayload,
      startsWith(WorkspaceEntry.runnerBinaryPrefix),
    );
    expect(
      WorkspaceEntry.decodeRunnerContent(runnerPayload!),
      orderedEquals(logoBytes),
    );

    final bundle = const WorkspaceExportService().build(
      workspace,
      exportedAt: DateTime.utc(2026, 9, 3),
    );
    final archive = ZipDecoder().decodeBytes(bundle.bytes);
    final exportedAsset = archive.findFile('assets/logo.png');
    expect(exportedAsset, isNotNull);
    expect(exportedAsset!.content, orderedEquals(logoBytes));
  });

  test('v2 snapshots remain UTF-8 compatible after the v3 upgrade', () {
    final json = <String, dynamic>{
      'formatVersion': 2,
      'entries': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'file-main',
          'path': 'lib/main.dart',
          'type': 'file',
          'content': 'void main() {}\n',
        },
      ],
      'baseEntries': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'file-main',
          'path': 'lib/main.dart',
          'type': 'file',
          'content': 'void main() {}\n',
        },
      ],
      'openFiles': <String>['lib/main.dart'],
      'activePath': 'lib/main.dart',
      'nextId': 2,
      'savedAt': DateTime.utc(2026, 9, 2).toIso8601String(),
      'expandedDirectoryIds': <String>[],
      'editorStates': <String, dynamic>{},
    };

    final snapshot = WorkspaceSnapshot.fromJson(json);
    expect(snapshot.formatVersion, 2);
    expect(snapshot.entries.single.encoding, WorkspaceFileEncoding.utf8);
    expect(snapshot.entries.single.content, 'void main() {}\n');
  });
}
