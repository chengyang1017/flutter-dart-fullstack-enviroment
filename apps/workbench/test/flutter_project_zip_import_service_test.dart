import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/project_import/services/flutter_project_zip_import_service.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/services/keyed_workspace_snapshot_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_catalog_store.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_project_library.dart';
import 'package:flutter_ui_playground/features/workspace/services/workspace_snapshot_store.dart';

void main() {
  const service = FlutterProjectZipImportService();

  test('imports one portable Flutter project and strips its ZIP root folder', () {
    final bundle = service.parse(
      _zip(<String, List<int>>{
        'sample_app/pubspec.yaml': _text('''
name: sample_app
environment:
  sdk: ^3.4.0
dependencies:
  flutter:
    sdk: flutter
flutter:
  uses-material-design: true
'''),
        'sample_app/lib/main.dart': _text(
          "void main() { print('hello'); }\n",
        ),
        'sample_app/lib/home.dart': _text('class HomeScreen {}\n'),
        'sample_app/analysis_options.yaml': _text('analyzer:\n  errors: {}\n'),
        'sample_app/android/app/src/main/MainActivity.kt': _text('class MainActivity'),
        'sample_app/web/icons/Icon-192.png': <int>[0, 1, 2, 3],
        'outside.txt': _text('not part of the selected Flutter root'),
      }),
      importedAt: DateTime.utc(2026, 9, 2),
    );

    expect(bundle.projectName, 'sample_app');
    expect(bundle.importedFileCount, 4);
    expect(bundle.ignoredFileCount, 2);
    expect(bundle.snapshot.activePath, 'lib/main.dart');
    expect(
      bundle.snapshot.entries.any((entry) => entry.path == 'lib/home.dart'),
      isTrue,
    );
    expect(
      bundle.snapshot.entries.any((entry) => entry.path.startsWith('android/')),
      isFalse,
    );
    expect(
      bundle.snapshot.entries.any((entry) => entry.path.startsWith('web/')),
      isFalse,
    );
  });

  test('imported project is stored as a clean importedFlutter workspace', () async {
    final bundle = service.parse(
      _zip(<String, List<int>>{
        'pubspec.yaml': _text('''
name: clean_import
dependencies:
  flutter:
    sdk: flutter
flutter:
  uses-material-design: true
'''),
        'lib/main.dart': _text('void main() {}\n'),
        'lib/feature.dart': _text('class Feature {}\n'),
      }),
    );

    final catalog = _MemoryWorkspaceProjectCatalogStore();
    final snapshots = _MemoryWorkspaceSnapshotStore();
    final library = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );
    final project = await library.createImportedFlutter(
      name: bundle.projectName,
      snapshot: bundle.snapshot,
    );

    expect(project.kind, WorkspaceProjectKind.importedFlutter);
    expect(library.activeProjectId, project.id);

    final reopenedLibrary = WorkspaceProjectLibrary(
      catalogStore: catalog,
      snapshotStore: snapshots,
    );
    expect(reopenedLibrary.activeProjectId, project.id);
    expect(
      reopenedLibrary.activeProject.kind,
      WorkspaceProjectKind.importedFlutter,
    );

    final controller = PlaygroundController(
      workspaceStore: KeyedWorkspaceSnapshotStore(
        delegate: snapshots,
        storageKey: project.storageKey,
      ),
    );
    expect(controller.restoredBrowserWorkspace, isTrue);
    expect(controller.workspace.isDirty, isFalse);
    expect(
      controller.workspace.entryAt('lib/feature.dart')?.content,
      'class Feature {}\n',
    );
    await controller.flushWorkspacePersistence();
    controller.dispose();
  });

  test('rejects binary portable assets instead of silently dropping them', () {
    final bytes = _zip(<String, List<int>>{
      'app/pubspec.yaml': _text('''
name: binary_app
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - assets/
'''),
      'app/lib/main.dart': _text('void main() {}\n'),
      'app/assets/logo.png': <int>[0, 137, 80, 78, 71, 1, 2, 3],
    });

    expect(
      () => service.parse(bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('assets/logo.png'),
        ),
      ),
    );
  });

  test('rejects ZIPs containing multiple runnable Flutter projects', () {
    final bytes = _zip(<String, List<int>>{
      'apps/one/pubspec.yaml': _text(_flutterPubspec('one')),
      'apps/one/lib/main.dart': _text('void main() {}\n'),
      'apps/two/pubspec.yaml': _text(_flutterPubspec('two')),
      'apps/two/lib/main.dart': _text('void main() {}\n'),
    });

    expect(
      () => service.parse(bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('multiple runnable Flutter projects'),
        ),
      ),
    );
  });

  test('rejects unsafe archive paths before importing project files', () {
    final bytes = _zip(<String, List<int>>{
      'pubspec.yaml': _text(_flutterPubspec('safe_app')),
      'lib/main.dart': _text('void main() {}\n'),
      '../outside.dart': _text('void unsafe() {}\n'),
    });

    expect(
      () => service.parse(bytes),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unsafe path'),
        ),
      ),
    );
  });
}

String _flutterPubspec(String name) => '''
name: $name
dependencies:
  flutter:
    sdk: flutter
flutter:
  uses-material-design: true
''';

List<int> _text(String value) => utf8.encode(value);

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, entry.value),
    );
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

class _MemoryWorkspaceProjectCatalogStore
    implements WorkspaceProjectCatalogStore {
  List<WorkspaceProject> _projects = <WorkspaceProject>[];
  String? _activeProjectId;

  @override
  List<WorkspaceProject> loadProjects() => _projects
      .map((project) => WorkspaceProject.fromJson(project.toJson()))
      .toList(growable: false);

  @override
  String? loadActiveProjectId() => _activeProjectId;

  @override
  Future<void> saveProjects(List<WorkspaceProject> projects) async {
    _projects = projects
        .map((project) => WorkspaceProject.fromJson(project.toJson()))
        .toList(growable: false);
  }

  @override
  Future<void> saveActiveProjectId(String projectId) async {
    _activeProjectId = projectId;
  }
}

class _MemoryWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
  final Map<String, WorkspaceSnapshot> _values = <String, WorkspaceSnapshot>{};

  @override
  WorkspaceSnapshot? load(String key) {
    final value = _values[key];
    return value == null ? null : WorkspaceSnapshot.fromJson(value.toJson());
  }

  @override
  Future<void> save(String key, WorkspaceSnapshot snapshot) async {
    _values[key] = WorkspaceSnapshot.fromJson(snapshot.toJson());
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
