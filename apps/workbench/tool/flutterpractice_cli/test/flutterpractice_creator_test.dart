import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutterpractice_cli/flutterpractice_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('creates a new scaffold then restores only portable workspace files', () async {
    final temp = await Directory.systemTemp.createTemp('flutterpractice-cli-test-');
    addTearDown(() => temp.delete(recursive: true));
    final output = p.join(temp.path, 'new_project');
    final commands = <_Command>[];

    Future<ProcessResult> fakeRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      commands.add(_Command(executable, arguments, workingDirectory));
      if (arguments.isNotEmpty && arguments.first == 'create') {
        final target = Directory(arguments.last);
        await Directory(p.join(target.path, 'lib')).create(recursive: true);
        await Directory(p.join(target.path, 'test')).create(recursive: true);
        await File(p.join(target.path, 'lib', 'main.dart'))
            .writeAsString('generated main');
        await File(p.join(target.path, 'test', 'widget_test.dart'))
            .writeAsString('generated test');
        await File(p.join(target.path, 'pubspec.yaml'))
            .writeAsString('name: generated_project\n');
        await File(p.join(target.path, 'analysis_options.yaml'))
            .writeAsString('generated analysis\n');
        await File(p.join(target.path, '.metadata')).writeAsString('generated');
      }
      return ProcessResult(1, 0, '', '');
    }

    final bytes = _packageBytes({
      'pubspec.yaml': _pubspec,
      'lib/main.dart': 'void main() {}\n',
      'lib/feature.dart': 'const feature = true;\n',
    });
    final creator = FlutterPracticeCreator(processRunner: fakeRunner);

    await creator.create(packageBytes: bytes, outputPath: output);

    expect(
      await File(p.join(output, 'lib', 'main.dart')).readAsString(),
      'void main() {}\n',
    );
    expect(
      await File(p.join(output, 'lib', 'feature.dart')).readAsString(),
      'const feature = true;\n',
    );
    expect(await File(p.join(output, 'test', 'widget_test.dart')).exists(), isFalse);
    expect(await File(p.join(output, '.metadata')).exists(), isTrue);
    expect(commands, hasLength(2));
    expect(commands.first.arguments.take(4), [
      'create',
      '--no-pub',
      '--project-name',
      'recreated_practice',
    ]);
    expect(commands.last.arguments, ['pub', 'get']);
    expect(commands.last.workingDirectory, p.normalize(p.absolute(output)));
  });

  test('refuses to touch an existing target directory', () async {
    final temp = await Directory.systemTemp.createTemp('flutterpractice-cli-exists-');
    addTearDown(() => temp.delete(recursive: true));
    final output = Directory(p.join(temp.path, 'existing'));
    await output.create();
    var processCalls = 0;

    final creator = FlutterPracticeCreator(
      processRunner: (
        String executable,
        List<String> arguments, {
        String? workingDirectory,
      }) async {
        processCalls += 1;
        return ProcessResult(1, 0, '', '');
      },
    );

    await expectLater(
      creator.create(
        packageBytes: _packageBytes({
          'pubspec.yaml': _pubspec,
          'lib/main.dart': 'void main() {}\n',
        }),
        outputPath: output.path,
      ),
      throwsA(isA<CreateProjectException>()),
    );
    expect(processCalls, 0);
  });

  test('removes a newly-created partial project when pub get fails', () async {
    final temp = await Directory.systemTemp.createTemp('flutterpractice-cli-rollback-');
    addTearDown(() => temp.delete(recursive: true));
    final output = p.join(temp.path, 'failed_project');

    Future<ProcessResult> fakeRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    }) async {
      if (arguments.first == 'create') {
        await Directory(arguments.last).create(recursive: true);
        return ProcessResult(1, 0, '', '');
      }
      return ProcessResult(2, 1, '', 'dependency failure');
    }

    final creator = FlutterPracticeCreator(processRunner: fakeRunner);
    await expectLater(
      creator.create(
        packageBytes: _packageBytes({
          'pubspec.yaml': _pubspec,
          'lib/main.dart': 'void main() {}\n',
        }),
        outputPath: output,
      ),
      throwsA(isA<CreateProjectException>()),
    );
    expect(await Directory(output).exists(), isFalse);
  });

  test('rejects generated runtime paths inside a practice package', () {
    final bytes = _packageBytes({
      'pubspec.yaml': _pubspec,
      'lib/main.dart': 'void main() {}\n',
      'build/evil.txt': 'not portable',
    });

    expect(
      () => FlutterPracticePackage.decode(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}

const _pubspec = '''
name: recreated_practice
description: Recreated practice project.
publish_to: none

environment:
  sdk: ^3.4.0

dependencies:
  flutter:
    sdk: flutter
''';

Uint8List _packageBytes(Map<String, String> files) {
  final archive = Archive();
  final payloadFiles = files.keys.toList()..sort();
  final manifest = jsonEncode({
    'formatVersion': 1,
    'projectType': 'flutter',
    'template': 'flutter-playground',
    'exportedAt': DateTime.utc(2026, 9, 3).toIso8601String(),
    'changes': const <Object>[],
    'payloadFiles': payloadFiles,
  });
  _addText(archive, 'manifest.json', manifest);
  for (final entry in files.entries) {
    _addText(archive, entry.key, entry.value);
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void _addText(Archive archive, String path, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}

class _Command {
  const _Command(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}
