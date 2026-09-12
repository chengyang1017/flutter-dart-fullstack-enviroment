import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/assets/services/asset_workspace_service.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';

void main() {
  test('default concept workspace already declares assets root', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    final service = AssetWorkspaceService(workspace);

    expect(service.hasAssetsDirectory, isTrue);
    expect(service.isAssetsDeclared, isTrue);
    expect(service.assetFiles, isEmpty);
  });

  test('imported asset remains binary and does not steal the active Dart file', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    final service = AssetWorkspaceService(workspace);
    final bytes = <int>[0, 1, 2, 3, 255, 128, 64];

    final path = service.addBinaryAsset(
      parentPath: 'assets',
      name: 'logo.png',
      bytes: bytes,
    );

    final asset = workspace.entryAt(path);
    expect(path, 'assets/logo.png');
    expect(asset, isNotNull);
    expect(asset!.isBinary, isTrue);
    expect(asset.bytes, orderedEquals(bytes));
    expect(workspace.activePath, 'lib/main.dart');
    expect(service.assetFiles.single.path, 'assets/logo.png');
  });

  test('adding an asset automatically restores missing pubspec declaration', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    workspace.updateFileContent(
      'pubspec.yaml',
      '''name: sample\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n''',
    );

    final service = AssetWorkspaceService(workspace);
    expect(service.isAssetsDeclared, isFalse);

    service.addBinaryAsset(
      parentPath: 'assets',
      name: 'photo.jpg',
      bytes: <int>[1, 2, 3],
    );

    final pubspec = workspace.entryAt('pubspec.yaml')!.content;
    expect(service.isAssetsDeclared, isTrue);
    expect(pubspec, contains('flutter:\n'));
    expect(pubspec, contains('  assets:\n    - assets/'));
  });

  test('nested asset folders stay inside boundary and register themselves', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    final service = AssetWorkspaceService(workspace);
    final folder = service.createFolder('assets', 'images');

    expect(folder, 'assets/images');
    expect(
      service.assetDirectories.map((entry) => entry.path),
      containsAll(<String>['assets', 'assets/images']),
    );
    expect(service.isDirectoryDeclared('assets/images'), isTrue);
    expect(
      workspace.entryAt('pubspec.yaml')!.content,
      contains('    - assets/images/'),
    );
    expect(
      () => service.createFolder('lib', 'bad'),
      throwsArgumentError,
    );
  });

  test('asset added inside nested folder keeps nested declaration', () {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    addTearDown(workspace.dispose);

    final service = AssetWorkspaceService(workspace);
    service.createFolder('assets', 'icons');
    service.addBinaryAsset(
      parentPath: 'assets/icons',
      name: 'home.png',
      bytes: <int>[7, 8, 9],
    );

    expect(service.isDirectoryDeclared('assets/icons'), isTrue);
    expect(workspace.entryAt('assets/icons/home.png')!.isBinary, isTrue);
  });
}
