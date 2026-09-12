import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_export_service.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';

void main() {
  test('export archive contains the complete portable text workspace', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    workspace.updateFileContent(
      'lib/main.dart',
      'void main() { print("changed"); }',
    );

    final bundle = const WorkspaceExportService().build(
      workspace,
      exportedAt: DateTime.utc(2026, 9, 2, 12),
    );

    final archive = ZipDecoder().decodeBytes(bundle.bytes);
    final names = archive.files.map((file) => file.name).toSet();

    expect(
      names,
      {
        'manifest.json',
        'analysis_options.yaml',
        'lib/main.dart',
        'pubspec.yaml',
      },
    );
    expect(
      bundle.manifest.payloadFiles,
      ['analysis_options.yaml', 'lib/main.dart', 'pubspec.yaml'],
    );
    expect(bundle.manifest.changes.length, 1);
    expect(bundle.manifest.changes.single.path, 'lib/main.dart');
  });

  test('manifest keeps changes while payload represents current source', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    workspace.createDirectory('lib', 'screens');
    workspace.moveEntry('lib/main.dart', 'lib/screens');
    workspace.deleteEntry('analysis_options.yaml');

    final bundle = const WorkspaceExportService().build(
      workspace,
      exportedAt: DateTime.utc(2026, 9, 2, 12),
    );
    final archive = ZipDecoder().decodeBytes(bundle.bytes);
    final manifestFile = archive.files.singleWhere(
      (file) => file.name == 'manifest.json',
    );
    final manifest = jsonDecode(
      utf8.decode(manifestFile.content as List<int>),
    ) as Map<String, dynamic>;

    final changes = (manifest['changes'] as List).cast<Map>();

    expect(
      changes.any(
        (change) =>
            change['type'] == 'moved' &&
            change['previousPath'] == 'lib/main.dart' &&
            change['path'] == 'lib/screens/main.dart',
      ),
      isTrue,
    );
    expect(
      changes.any(
        (change) =>
            change['type'] == 'deleted' &&
            change['path'] == 'analysis_options.yaml',
      ),
      isTrue,
    );
    expect(
      bundle.manifest.payloadFiles,
      ['lib/screens/main.dart', 'pubspec.yaml'],
    );
  });
}
