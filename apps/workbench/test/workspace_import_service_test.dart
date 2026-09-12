import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_export_service.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_import_service.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';

void main() {
  test('export then import restores changed workspace structure and contents', () {
    const baseMain = 'void main() {}';
    final source = WorkspaceController.flutterPlayground(
      mainDartContent: baseMain,
    );
    final target = WorkspaceController.flutterPlayground(
      mainDartContent: baseMain,
    );
    addTearDown(source.dispose);
    addTearDown(target.dispose);

    source.createDirectory('lib', 'screens');
    source.moveEntry('lib/main.dart', 'lib/screens');
    source.updateFileContent(
      'lib/screens/main.dart',
      'void main() { print("portable"); }',
    );
    source.createFile(
      'lib/screens',
      'helper.dart',
      content: 'String helper() => "ok";',
    );
    source.deleteEntry('analysis_options.yaml');

    final bundle = const WorkspaceExportService().build(
      source,
      exportedAt: DateTime.utc(2026, 9, 2, 13),
    );

    const WorkspaceImportService().apply(bundle.bytes, target);

    expect(target.entryAt('lib/main.dart'), isNull);
    expect(target.entryAt('lib/screens')?.isDirectory, isTrue);
    expect(
      target.entryAt('lib/screens/main.dart')?.content,
      'void main() { print("portable"); }',
    );
    expect(
      target.entryAt('lib/screens/helper.dart')?.content,
      'String helper() => "ok";',
    );
    expect(target.entryAt('analysis_options.yaml'), isNull);

    final sourceChanges = source.changes
        .map((change) =>
            '${change.type.name}|${change.previousPath ?? ''}|${change.path}')
        .toSet();
    final targetChanges = target.changes
        .map((change) =>
            '${change.type.name}|${change.previousPath ?? ''}|${change.path}')
        .toSet();

    expect(targetChanges, sourceChanges);
  });

  test('deleted child follows a relocated parent during import', () {
    const baseMain = 'void main() {}';
    final source = WorkspaceController.flutterPlayground(
      mainDartContent: baseMain,
    );
    final target = WorkspaceController.flutterPlayground(
      mainDartContent: baseMain,
    );
    addTearDown(source.dispose);
    addTearDown(target.dispose);

    source.renameEntry('lib', 'src');
    source.deleteEntry('src/main.dart');

    final bundle = const WorkspaceExportService().build(
      source,
      exportedAt: DateTime.utc(2026, 9, 2, 13),
    );

    const WorkspaceImportService().apply(bundle.bytes, target);

    expect(target.entryAt('lib'), isNull);
    expect(target.entryAt('src')?.isDirectory, isTrue);
    expect(target.entryAt('src/main.dart'), isNull);
  });
}
