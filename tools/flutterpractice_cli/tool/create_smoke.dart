import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutterpractice_cli/flutterpractice_cli.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('flutterpractice-create-smoke-');
  try {
    final output = p.join(temp.path, 'recreated_project');
    final packageBytes = _buildPackage();
    final creator = FlutterPracticeCreator(log: stdout.writeln);

    await creator.create(packageBytes: packageBytes, outputPath: output);

    final mainFile = File(p.join(output, 'lib', 'main.dart'));
    final generatedWeb = File(p.join(output, 'web', 'index.html'));
    final dartTool = Directory(p.join(output, '.dart_tool'));

    if (!await mainFile.exists()) {
      throw StateError('Restored lib/main.dart is missing.');
    }
    if (!await generatedWeb.exists()) {
      throw StateError('flutter create did not generate web/index.html.');
    }
    if (!await dartTool.exists()) {
      throw StateError('flutter pub get did not create .dart_tool.');
    }
    final mainSource = await mainFile.readAsString();
    if (!mainSource.contains('Practice package restored')) {
      throw StateError('Portable source was not restored into the new project.');
    }

    final analyze = await Process.run(
      'flutter',
      const ['analyze', '--no-pub'],
      workingDirectory: output,
    );
    stdout.write(analyze.stdout);
    stderr.write(analyze.stderr);
    if (analyze.exitCode != 0) {
      throw StateError('flutter analyze failed with code ${analyze.exitCode}.');
    }

    stdout.writeln('[smoke] flutterpractice create rebuilt a valid Flutter project.');
  } finally {
    if (await temp.exists()) await temp.delete(recursive: true);
  }
}

Uint8List _buildPackage() {
  const pubspec = '''
name: recreated_practice
description: FlutterPractice CLI smoke project.
publish_to: none

environment:
  sdk: ^3.4.0

dependencies:
  flutter:
    sdk: flutter
''';
  const mainDart = '''
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Practice package restored'),
        ),
      ),
    ),
  );
}
''';
  final files = <String, String>{
    'lib/main.dart': mainDart,
    'pubspec.yaml': pubspec,
  };
  final payloadFiles = files.keys.toList()..sort();
  final archive = Archive();
  _addText(
    archive,
    'manifest.json',
    jsonEncode({
      'formatVersion': 1,
      'projectType': 'flutter',
      'template': 'flutter-playground',
      'exportedAt': DateTime.utc(2026, 9, 3).toIso8601String(),
      'changes': const <Object>[],
      'payloadFiles': payloadFiles,
    }),
  );
  for (final entry in files.entries) {
    _addText(archive, entry.key, entry.value);
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void _addText(Archive archive, String path, String content) {
  final bytes = utf8.encode(content);
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}
