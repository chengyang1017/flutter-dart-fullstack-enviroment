import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_export_service.dart';
import 'package:flutter_ui_playground/features/export/services/workspace_import_service.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';
import 'package:flutter_ui_playground/features/workspace/services/dart_frog_workspace_service.dart';
import 'package:flutter_ui_playground/features/workspace/services/serverpod_workspace_service.dart';

void main() {
  const service = ServerpodWorkspaceService();

  WorkspaceController createWorkspace() {
    return WorkspaceController.flutterPlayground(
      mainDartContent: '''
class PracticeExample {}
const chineseName = '万文社';
const englishName = 'Glyphora';
''',
    );
  }

  test('Serverpod service adds standard Mini server and client packages', () {
    final workspace = createWorkspace();
    addTearDown(workspace.dispose);

    service.ensureEnabled(workspace);

    expect(service.isEnabled(workspace), isTrue);
    expect(
      workspace.entryAt(ServerpodWorkspaceService.serverPubspecPath)!.content,
      contains('serverpod: 3.4.13'),
    );
    expect(
      workspace.entryAt(ServerpodWorkspaceService.clientPubspecPath)!.content,
      contains('serverpod_client: 3.4.13'),
    );
    expect(
      workspace.entryAt(ServerpodWorkspaceService.generatorConfigPath)!.content,
      contains('client_package_path: ../practice_client'),
    );
    expect(
      workspace.entryAt(ServerpodWorkspaceService.greetingEndpointPath)!.content,
      contains('class GreetingEndpoint extends Endpoint'),
    );
    expect(
      workspace.entryAt(ServerpodWorkspaceService.apiClientPath)!.content,
      contains("String.fromEnvironment('SERVERPOD_URL')"),
    );
    expect(
      workspace.entryAt('pubspec.yaml')!.content,
      contains('path: serverpod/practice_client'),
    );
    expect(
      workspace.entryAt('lib/main.dart')!.content,
      contains('ServerpodPractice'),
    );
  });

  test('enabling Serverpod twice is idempotent', () {
    final workspace = createWorkspace();
    addTearDown(workspace.dispose);

    service.ensureEnabled(workspace);
    final firstPaths = workspace.entries.map((entry) => entry.path).toList();
    final firstPubspec = workspace.entryAt('pubspec.yaml')!.content;

    service.ensureEnabled(workspace);

    expect(
      workspace.entries.map((entry) => entry.path).toList(),
      firstPaths,
    );
    expect(workspace.entryAt('pubspec.yaml')!.content, firstPubspec);
    expect(
      RegExp(r'^\s{2}practice_client\s*:', multiLine: true)
          .allMatches(firstPubspec)
          .length,
      1,
    );
  });

  test('Serverpod and Dart Frog cannot be enabled in the same workspace', () {
    final workspace = createWorkspace();
    addTearDown(workspace.dispose);

    const DartFrogWorkspaceService().ensureEnabled(workspace);

    expect(
      () => service.ensureEnabled(workspace),
      throwsA(isA<StateError>()),
    );
  });

  test('portable Serverpod export can be imported again', () {
    final source = createWorkspace();
    final target = createWorkspace();
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    service.ensureEnabled(source);

    final bundle = const WorkspaceExportService().build(
      source,
      exportedAt: DateTime.utc(2026, 9, 2),
    );

    expect(bundle.manifest.projectType, 'flutter-serverpod-mini');
    expect(bundle.manifest.template, 'flutter-playground');
    expect(
      bundle.manifest.payloadFiles,
      contains(ServerpodWorkspaceService.greetingEndpointPath),
    );

    final imported = const WorkspaceImportService().apply(bundle.bytes, target);

    expect(imported.projectType, 'flutter-serverpod-mini');
    expect(service.isEnabled(target), isTrue);
    expect(
      target.entryAt(ServerpodWorkspaceService.greetingEndpointPath)?.content,
      contains('class GreetingEndpoint extends Endpoint'),
    );
    expect(
      target.entryAt('pubspec.yaml')?.content,
      contains('path: serverpod/practice_client'),
    );
  });
}
