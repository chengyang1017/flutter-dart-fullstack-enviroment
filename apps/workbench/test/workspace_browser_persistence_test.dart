import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_change.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  test('browser workspace autosave restores files, tabs and dirty state', () async {
    final store = _MemoryWorkspaceSnapshotStore();

    final first = PlaygroundController(workspaceStore: store);
    first.workspace.updateFileContent(
      'lib/main.dart',
      '${PlaygroundController.exampleCode}\n// persisted change',
    );
    first.workspace.createDirectory('lib', 'screens');
    first.workspace.createFile(
      'lib/screens',
      'home.dart',
      content: 'class HomeScreen {}',
    );
    first.workspace.openFile('pubspec.yaml');

    await first.flushWorkspacePersistence();
    first.dispose();

    final second = PlaygroundController(workspaceStore: store);
    addTearDown(second.dispose);

    expect(second.restoredBrowserWorkspace, isTrue);
    expect(
      second.workspace.entryAt('lib/main.dart')?.content,
      contains('// persisted change'),
    );
    expect(
      second.workspace.entryAt('lib/screens/home.dart')?.content,
      'class HomeScreen {}',
    );
    expect(second.workspace.activePath, 'pubspec.yaml');
    expect(
      second.workspace.openFiles,
      containsAll(<String>['lib/main.dart', 'lib/screens/home.dart', 'pubspec.yaml']),
    );
    expect(second.workspace.isDirty, isTrue);
    expect(
      second.workspace.changes.any(
        (change) =>
            change.type == WorkspaceChangeType.modified &&
            change.path == 'lib/main.dart',
      ),
      isTrue,
    );
    expect(
      second.workspace.changes.any(
        (change) =>
            change.type == WorkspaceChangeType.created &&
            change.path == 'lib/screens/home.dart',
      ),
      isTrue,
    );
  });

  test('browser workspace restores explorer, selection and scroll per file', () async {
    final store = _MemoryWorkspaceSnapshotStore();

    final first = PlaygroundController(workspaceStore: store);
    first.workspace.setDirectoryExpanded('lib', false);
    first.workspace.createDirectory('lib', 'screens');
    first.selectWorkspaceFile('pubspec.yaml');

    final pubspecId = first.workspace.entryAt('pubspec.yaml')!.id;
    first.workspace.updateEditorStateByEntryId(
      pubspecId,
      const WorkspaceEditorState(
        verticalOffset: 144,
        horizontalOffset: 28,
      ),
    );
    first.textController.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 3,
    );

    await first.flushWorkspacePersistence();
    first.dispose();

    final second = PlaygroundController(workspaceStore: store);
    addTearDown(second.dispose);

    expect(second.workspace.activePath, 'pubspec.yaml');
    expect(second.workspace.isDirectoryExpanded('lib'), isFalse);
    expect(second.workspace.isDirectoryExpanded('lib/screens'), isTrue);
    expect(second.textController.selection.baseIndex, 1);
    expect(second.textController.selection.baseOffset, 3);
    expect(second.textController.selection.extentIndex, 1);
    expect(second.textController.selection.extentOffset, 3);
    expect(
      second.editorScrollController.verticalScroller.initialScrollOffset,
      144,
    );
    expect(
      second.editorScrollController.horizontalScroller.initialScrollOffset,
      28,
    );
  });

  test('workspace snapshot JSON round trip preserves base snapshot metadata', () {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);

    controller.workspace.renameEntry('lib/main.dart', 'app.dart');
    final original = controller.workspace.createSnapshot();
    final decoded = WorkspaceSnapshot.fromJson(original.toJson());

    controller.workspace.restoreSnapshot(decoded);

    expect(controller.workspace.activePath, 'lib/app.dart');
    expect(
      controller.workspace.changes.single.type,
      WorkspaceChangeType.renamed,
    );
    expect(controller.workspace.changes.single.previousPath, 'lib/main.dart');
  });

  test('v1 browser snapshots remain compatible with v2 UI-state restore', () {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);

    final legacyJson = controller.workspace.createSnapshot().toJson()
      ..['formatVersion'] = 1
      ..remove('expandedDirectoryIds')
      ..remove('editorStates');

    final decoded = WorkspaceSnapshot.fromJson(legacyJson);
    controller.workspace.restoreSnapshot(decoded);

    expect(decoded.formatVersion, 1);
    expect(controller.workspace.isDirectoryExpanded('lib'), isTrue);
    expect(controller.workspace.isDirectoryExpanded('assets'), isTrue);
    expect(controller.workspace.editorStateForPath('lib/main.dart'), isNull);
  });
}

class _MemoryWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
  final Map<String, WorkspaceSnapshot> _values = <String, WorkspaceSnapshot>{};

  @override
  WorkspaceSnapshot? load(String key) => _values[key];

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    _values[key] = WorkspaceSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
