import 'dart:io';

import 'package:flutterpractice_cli/flutterpractice_cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await _run(arguments);

  if (code != 0) {
    exitCode = code;
  }
}

Future<int> _run(
  List<String> arguments,
) async {
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    _printUsage();
    return 0;
  }

  switch (arguments.first) {
    case 'create':
      return _runCreate(
        arguments.skip(1).toList(),
      );

    case 'apply':
      stderr.writeln(
        'ApplyKit apply is not implemented yet.',
      );
      return 64;

    default:
      stderr.writeln(
        'Unknown command: ${arguments.first}',
      );
      _printUsage();
      return 64;
  }
}

Future<int> _runCreate(
  List<String> arguments,
) async {
  if (arguments.isEmpty) {
    stderr.writeln(
      'Missing .applykit package path.',
    );

    _printUsage();
    return 64;
  }

  final packageFile = File(
    arguments.first,
  );

  String? outputPath;
  var flutterExecutable = 'flutter';

  for (var index = 1; index < arguments.length; index++) {
    final argument = arguments[index];

    switch (argument) {
      case '--output':
        if (index + 1 >= arguments.length) {
          stderr.writeln(
            '--output requires a new directory path.',
          );
          return 64;
        }

        outputPath = arguments[++index];

        break;

      case '--flutter':
        if (index + 1 >= arguments.length) {
          stderr.writeln(
            '--flutter requires an executable path.',
          );
          return 64;
        }

        flutterExecutable = arguments[++index];

        break;

      default:
        stderr.writeln(
          'Unknown option: $argument',
        );
        return 64;
    }
  }

  if (outputPath == null || outputPath.trim().isEmpty) {
    stderr.writeln(
      '--output is required.',
    );

    return 64;
  }

  if (!await packageFile.exists()) {
    stderr.writeln(
      'ApplyKit package does not exist: '
      '${packageFile.path}',
    );

    return 66;
  }

  if (!packageFile.path.toLowerCase().endsWith('.applykit')) {
    stderr.writeln(
      'Expected an .applykit package.',
    );

    return 65;
  }

  try {
    final creator = FlutterPracticeCreator(
      flutterExecutable: flutterExecutable,
      log: stdout.writeln,
    );

    await creator.create(
      packageBytes: await packageFile.readAsBytes(),
      outputPath: outputPath,
    );

    stdout.writeln(
      'ApplyKit project created successfully.',
    );

    return 0;
  } on FormatException catch (error) {
    stderr.writeln(
      'Invalid ApplyKit package: '
      '${error.message}',
    );

    return 65;
  } on CreateProjectException catch (error) {
    stderr.writeln(
      error.message,
    );

    return 1;
  } catch (error) {
    stderr.writeln(
      'ApplyKit failed: $error',
    );

    return 1;
  }
}

void _printUsage() {
  stdout.writeln(
    '''
ApplyKit

Portable project changes for Flutter projects.

Usage:

  applykit create <file.applykit> --output <new-directory>

  applykit apply <file.applykit>

Commands:

  create
      Create a new Flutter project and apply the package.

  apply
      Apply the package to an existing Git project.

Options:

  --output <path>
      Output directory for a new project.

  --flutter <path>
      Flutter executable.
      Default: flutter

  -h, --help
      Show this help.
''',
  );
}
