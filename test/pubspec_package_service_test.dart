import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/packages/models/package_models.dart';
import 'package:flutter_ui_playground/features/packages/services/pubspec_package_service.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';

void main() {
  const service = PubspecPackageService();

  group('PubspecPackageService', () {
    test('reads declared, resolved, source and dependency group separately', () {
      final workspace = _workspaceWithPubspec();
      addTearDown(workspace.dispose);

      workspace.createFile(
        '',
        'pubspec.lock',
        content: '''
packages:
  build_runner:
    dependency: "direct dev"
    source: hosted
    version: "2.4.15"
  provider:
    dependency: "direct main"
    source: hosted
    version: "6.1.5"
''',
      );

      final dependencies = service.read(workspace);
      final provider = dependencies.singleWhere(
        (dependency) => dependency.name == 'provider',
      );
      final buildRunner = dependencies.singleWhere(
        (dependency) => dependency.name == 'build_runner',
      );
      final flutter = dependencies.singleWhere(
        (dependency) => dependency.name == 'flutter',
      );

      expect(provider.constraint, '^6.1.2');
      expect(provider.resolvedVersion, '6.1.5');
      expect(provider.source, PackageDependencySource.hosted);
      expect(provider.group, PackageDependencyGroup.dependencies);

      expect(buildRunner.constraint, '2.4.13');
      expect(buildRunner.resolvedVersion, '2.4.15');
      expect(buildRunner.group, PackageDependencyGroup.devDependencies);

      expect(flutter.source, PackageDependencySource.sdk);
      expect(flutter.constraint, 'sdk: flutter');
    });

    test('moves a hosted package between dependency groups without duplicates', () {
      final workspace = _workspaceWithPubspec();
      addTearDown(workspace.dispose);

      service.upsertHostedDependency(
        workspace,
        packageName: 'provider',
        version: '6.1.5',
        group: PackageDependencyGroup.devDependencies,
        compatibleRange: false,
      );

      final content = workspace.entryAt('pubspec.yaml')!.content;
      expect(
        RegExp(r'^  provider:', multiLine: true).allMatches(content).length,
        1,
      );
      expect(
        RegExp(
          r'dev_dependencies:\n(?:.|\n)*?  provider: 6\.1\.5',
        ).hasMatch(content),
        isTrue,
      );

      final provider = service.read(workspace).singleWhere(
        (dependency) => dependency.name == 'provider',
      );
      expect(provider.group, PackageDependencyGroup.devDependencies);
      expect(provider.constraint, '6.1.5');
    });

    test('adds a new hosted dependency with caret constraint', () {
      final workspace = _workspaceWithPubspec();
      addTearDown(workspace.dispose);

      service.upsertHostedDependency(
        workspace,
        packageName: 'dio',
        version: '5.9.0',
        group: PackageDependencyGroup.dependencies,
        compatibleRange: true,
      );

      final dio = service.read(workspace).singleWhere(
        (dependency) => dependency.name == 'dio',
      );
      expect(dio.constraint, '^5.9.0');
      expect(dio.source, PackageDependencySource.hosted);
      expect(dio.group, PackageDependencyGroup.dependencies);
    });

    test('removes only the selected dependency', () {
      final workspace = _workspaceWithPubspec();
      addTearDown(workspace.dispose);

      service.removeDependency(
        workspace,
        packageName: 'provider',
        group: PackageDependencyGroup.dependencies,
      );

      final names = service.read(workspace).map((dependency) => dependency.name);
      expect(names, isNot(contains('provider')));
      expect(names, contains('flutter'));
      expect(names, contains('build_runner'));
    });
  });
}

WorkspaceController _workspaceWithPubspec() {
  final workspace = WorkspaceController.flutterPlayground(
    mainDartContent: 'void main() {}',
  );

  workspace.updateFileContent(
    'pubspec.yaml',
    '''
name: package_manager_test
environment:
  sdk: ^3.10.0

dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: 2.4.13

flutter:
  uses-material-design: true
''',
  );

  return workspace;
}
