import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_change.dart';

void main() {
  group('WorkspaceController', () {
    test('tracks content changes and clears dirty state when restored', () {
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: 'Text(\'hello\')',
      );
      addTearDown(workspace.dispose);

      workspace.updateFileContent('lib/main.dart', 'Text(\'changed\')');

      expect(workspace.isDirty, isTrue);
      expect(
        workspace.changes.any(
          (change) =>
              change.type == WorkspaceChangeType.modified &&
              change.path == 'lib/main.dart',
        ),
        isTrue,
      );

      workspace.updateFileContent('lib/main.dart', 'Text(\'hello\')');
      expect(workspace.isDirty, isFalse);
    });

    test('tracks rename using the stable entry id', () {
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: 'Text(\'hello\')',
      );
      addTearDown(workspace.dispose);

      workspace.renameEntry('lib/main.dart', 'app.dart');

      expect(workspace.entryAt('lib/main.dart'), isNull);
      expect(workspace.entryAt('lib/app.dart'), isNotNull);
      expect(
        workspace.changes.any(
          (change) =>
              change.type == WorkspaceChangeType.renamed &&
              change.previousPath == 'lib/main.dart' &&
              change.path == 'lib/app.dart',
        ),
        isTrue,
      );
    });

    test('tracks a move separately from create/delete', () {
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: 'Text(\'hello\')',
      );
      addTearDown(workspace.dispose);

      workspace.createDirectory('lib', 'screens');
      workspace.moveEntry('lib/main.dart', 'lib/screens');

      expect(workspace.entryAt('lib/screens/main.dart'), isNotNull);
      expect(
        workspace.changes.any(
          (change) =>
              change.type == WorkspaceChangeType.moved &&
              change.previousPath == 'lib/main.dart' &&
              change.path == 'lib/screens/main.dart',
        ),
        isTrue,
      );
    });

    test('new file removed in the same session leaves no change', () {
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: 'Text(\'hello\')',
      );
      addTearDown(workspace.dispose);

      final path = workspace.createFile('lib', 'temporary.dart');
      workspace.deleteEntry(path);

      expect(
        workspace.changes.any((change) => change.path == path),
        isFalse,
      );
    });

    test('resetWorkspace restores the base snapshot', () {
      final workspace = WorkspaceController.flutterPlayground(
        mainDartContent: 'Text(\'hello\')',
      );
      addTearDown(workspace.dispose);

      workspace.createFile('lib', 'new_file.dart');
      workspace.updateFileContent('lib/main.dart', 'changed');
      workspace.deleteEntry('pubspec.yaml');

      workspace.resetWorkspace();

      expect(workspace.isDirty, isFalse);
      expect(workspace.activePath, 'lib/main.dart');
      expect(workspace.entryAt('pubspec.yaml'), isNotNull);
      expect(workspace.entryAt('lib/new_file.dart'), isNull);
      expect(workspace.entryAt('lib/main.dart')?.content, 'Text(\'hello\')');
    });
  });
}
