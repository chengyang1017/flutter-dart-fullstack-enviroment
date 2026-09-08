import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'practice_package.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

class FlutterPracticeCreator {
  FlutterPracticeCreator({
    this.flutterExecutable = 'flutter',
    ProcessRunner? processRunner,
    void Function(String message)? log,
  })  : _processRunner = processRunner ?? _defaultProcessRunner,
        _log = log ?? _ignoreLog;

  final String flutterExecutable;
  final ProcessRunner _processRunner;
  final void Function(String message) _log;

  Future<Directory> create({
    required Uint8List packageBytes,
    required String outputPath,
  }) async {
    final practicePackage = FlutterPracticePackage.decode(
      packageBytes,
    );

    final target = Directory(
      p.normalize(
        p.absolute(outputPath),
      ),
    );

    if (await target.exists()) {
      throw CreateProjectException(
        'Target directory already exists: '
        '${target.path}',
      );
    }

    final parent = target.parent;

    if (!await parent.exists()) {
      throw CreateProjectException(
        'Target parent directory does not exist: '
        '${parent.path}',
      );
    }

    try {
      _log(
        'Creating Flutter project: '
        '${practicePackage.projectName}',
      );

      await _runChecked(
        flutterExecutable,
        [
          'create',
          '--no-pub',
          '--platforms=${practicePackage.flutterPlatforms.join(',')}',
          '--project-name',
          practicePackage.projectName,
          target.path,
        ],
        action: 'flutter create',
      );

      _log(
        'Applying ApplyKit changes...',
      );

      await _applyChanges(
        target,
        practicePackage,
      );

      _log(
        'Resolving Flutter dependencies...',
      );

      await _runChecked(
        flutterExecutable,
        const [
          'pub',
          'get',
        ],
        workingDirectory: target.path,
        action: 'flutter pub get',
      );

      _log(
        'Created new Flutter project: '
        '${target.path}',
      );

      return target;
    } catch (error) {
      if (await target.exists()) {
        try {
          await target.delete(
            recursive: true,
          );
        } catch (_) {}
      }

      rethrow;
    }
  }

  Future<void> _applyChanges(
    Directory target,
    FlutterPracticePackage package,
  ) async {
    for (final change in package.changes) {
      switch (change.type) {
        case 'created':
        case 'modified':
          await _writeFile(
            target,
            package,
            change.path,
          );
          break;

        case 'deleted':
          await _deletePath(
            target,
            change.path,
          );
          break;

        case 'renamed':
        case 'moved':
          final previousPath = change.previousPath;

          if (previousPath == null) {
            throw CreateProjectException(
              '${change.type} requires '
              'previousPath: ${change.path}',
            );
          }

          await _deletePath(
            target,
            previousPath,
          );

          await _writeFile(
            target,
            package,
            change.path,
          );
          break;

        default:
          throw CreateProjectException(
            'Unsupported ApplyKit change: '
            '${change.type}',
          );
      }
    }
  }

  Future<void> _writeFile(
    Directory target,
    FlutterPracticePackage package,
    String relativePath,
  ) async {
    final content = package.files[relativePath];

    if (content == null) {
      throw CreateProjectException(
        'ApplyKit payload is missing: '
        '$relativePath',
      );
    }

    final destination = _safeFile(
      target,
      relativePath,
    );

    await destination.parent.create(
      recursive: true,
    );

    await destination.writeAsBytes(
      content,
      flush: true,
    );

    _log(
      'Applied: $relativePath',
    );
  }

  Future<void> _deletePath(
    Directory target,
    String relativePath,
  ) async {
    final path = _safePath(
      target,
      relativePath,
    );

    final file = File(path);

    if (await file.exists()) {
      await file.delete();

      _log(
        'Deleted: $relativePath',
      );

      return;
    }

    final directory = Directory(path);

    if (await directory.exists()) {
      await directory.delete(
        recursive: true,
      );

      _log(
        'Deleted: $relativePath',
      );
    }
  }

  File _safeFile(
    Directory target,
    String relativePath,
  ) {
    return File(
      _safePath(
        target,
        relativePath,
      ),
    );
  }

  String _safePath(
    Directory target,
    String relativePath,
  ) {
    if (relativePath.isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.contains('\\') ||
        RegExp(
          r'^[A-Za-z]:',
        ).hasMatch(relativePath)) {
      throw CreateProjectException(
        'Unsafe ApplyKit path: '
        '$relativePath',
      );
    }

    final segments = relativePath.split('/');

    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw CreateProjectException(
        'Unsafe ApplyKit path: '
        '$relativePath',
      );
    }

    final root = p.normalize(
      p.absolute(
        target.path,
      ),
    );

    final destination = p.normalize(
      p.joinAll(
        [
          root,
          ...segments,
        ],
      ),
    );

    if (!p.isWithin(
      root,
      destination,
    )) {
      throw CreateProjectException(
        'ApplyKit path escaped project: '
        '$relativePath',
      );
    }

    return destination;
  }

  Future<void> _runChecked(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    required String action,
  }) async {
    final result = await _processRunner(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );

    if (result.exitCode == 0) {
      return;
    }

    final stderrText = '${result.stderr}'.trim();

    final stdoutText = '${result.stdout}'.trim();

    final detail = stderrText.isNotEmpty ? stderrText : stdoutText;

    throw CreateProjectException(
      detail.isEmpty
          ? '$action failed with exit code '
              '${result.exitCode}.'
          : '$action failed with exit code '
              '${result.exitCode}: $detail',
    );
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
  }

  static void _ignoreLog(
    String _,
  ) {}
}

class CreateProjectException implements Exception {
  const CreateProjectException(
    this.message,
  );

  final String message;

  @override
  String toString() => message;
}
