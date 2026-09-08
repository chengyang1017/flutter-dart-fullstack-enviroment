import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'practice_package.dart';

typedef ApplyKitProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

class ApplyKitProjectApplier {
  ApplyKitProjectApplier({
    ApplyKitProcessRunner? processRunner,
    void Function(String message)? log,
  })  : _processRunner = processRunner ?? _defaultProcessRunner,
        _log = log ?? _ignoreLog;

  final ApplyKitProcessRunner _processRunner;
  final void Function(String message) _log;

  bool _baseContentMatches(
  List<int> current,
  List<int> expected,
) {
  if (_bytesEqual(current, expected)) {
    return true;
  }

  try {
    final currentText = utf8.decode(
      current,
      allowMalformed: false,
    );

    final expectedText = utf8.decode(
      expected,
      allowMalformed: false,
    );

    return _normalizeNewlines(currentText) ==
        _normalizeNewlines(expectedText);
  } on FormatException {
    return false;
  }
}

String _normalizeNewlines(
  String value,
) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
}

  bool _bytesEqual(
  List<int> a,
  List<int> b,
) {
  if (a.length != b.length) {
    return false;
  }

  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }

  return true;
}

  Future<void> apply({
    required File packageFile,
    Directory? projectDirectory,
  }) async {
    final project = projectDirectory ?? Directory.current;

    final package = FlutterPracticePackage.decode(
      await packageFile.readAsBytes(),
    );

    await _ensureGitRepository(project);
    await _ensureCleanWorkingTree(project);
    await _ensureFlutterProject(project);

    await _ensurePackageBaseMatches(
      project,
      package,
    );

    final originalBranch = await _currentBranch(project);

    final branchName = await _createUniqueBranchName(
      project,
    );

    _log(
      'Base branch: $originalBranch',
    );

    _log(
      'Creating ApplyKit branch: $branchName',
    );

    await _runGitChecked(
      project,
      [
        'switch',
        '-c',
        branchName,
      ],
      action: 'create ApplyKit branch',
    );

    var commitCreated = false;

    try {
      await _applyChanges(
        project,
        package,
      );

      final changed = await _hasWorkingTreeChanges(
        project,
      );

      if (!changed) {
        _log(
          'ApplyKit package produced no file changes.',
        );

        await _runGitChecked(
          project,
          [
            'switch',
            originalBranch,
          ],
          action: 'return to base branch',
        );

        await _runGitChecked(
          project,
          [
            'branch',
            '-D',
            branchName,
          ],
          action: 'remove empty ApplyKit branch',
        );

        return;
      }

      await _runGitChecked(
        project,
        const [
          'add',
          '-A',
        ],
        action: 'stage ApplyKit changes',
      );

      final stagedChanged =
    await _hasStagedChanges(project);

if (!stagedChanged) {
  _log(
    'ApplyKit package produced no effective Git changes.',
  );

  await _runGitChecked(
    project,
    [
      'switch',
      originalBranch,
    ],
    action: 'return to base branch',
  );

  await _runGitChecked(
      project,
      [
        'branch',
        '-D',
        branchName,
      ],
      action: 'remove empty ApplyKit branch',
    );

    return;
  }

      await _runGitChecked(
        project,
        [
          'commit',
          '-m',
          'Apply ApplyKit package',
        ],
        action: 'commit ApplyKit changes',
      );

      commitCreated = true;

      await _runGitChecked(
        project,
        [
          'switch',
          originalBranch,
        ],
        action: 'return to base branch',
      );

      _log(
        'Merging $branchName into $originalBranch...',
      );

      final mergeResult = await _processRunner(
        'git',
        [
          'merge',
          '--no-ff',
          branchName,
        ],
        workingDirectory: project.path,
      );

      if (mergeResult.exitCode != 0) {
        final detail = _processDetail(
          mergeResult,
        );

        throw ApplyKitMergeConflictException(
          branchName: branchName,
          originalBranch: originalBranch,
          detail: detail,
        );
      }

      _log(
        'ApplyKit changes merged successfully.',
      );

      _log(
        'ApplyKit branch kept: $branchName',
      );
    } catch (error) {
      if (!commitCreated) {
        await _tryRestoreBeforeCommitFailure(
          project,
          originalBranch: originalBranch,
          branchName: branchName,
        );
      }

      rethrow;
    }
  }

  Future<void> _ensurePackageBaseMatches(
  Directory project,
  FlutterPracticePackage package,
) async {
  final conflicts = <String>[];

  for (final change in package.changes) {
    switch (change.type) {
      case 'created':
        if (await _pathExists(
          project,
          change.path,
        )) {
          conflicts.add(
            'Created target already exists: ${change.path}',
          );
        }
        break;

      case 'modified':
      case 'deleted':
        final mismatch = await _baseMismatchForFile(
          project,
          package,
          change.path,
        );

        if (mismatch != null) {
          conflicts.add(mismatch);
        }
        break;

      case 'renamed':
      case 'moved':
        final previousPath = change.previousPath;

        if (previousPath == null) {
          throw ApplyKitException(
            '${change.type} change requires previousPath: '
            '${change.path}',
          );
        }

        final mismatch = await _baseMismatchForFile(
          project,
          package,
          previousPath,
        );

        if (mismatch != null) {
          conflicts.add(mismatch);
        }

        if (change.path != previousPath &&
            await _pathExists(
              project,
              change.path,
            )) {
          conflicts.add(
            'Rename/move target already exists: ${change.path}',
          );
        }
        break;

      default:
        throw ApplyKitException(
          'Unsupported ApplyKit change type: '
          '${change.type}',
        );
    }
  }

  if (conflicts.isNotEmpty) {
    throw ApplyKitBaseMismatchException(
      conflicts,
    );
  }
}

Future<String?> _baseMismatchForFile(
  Directory project,
  FlutterPracticePackage package,
  String relativePath,
) async {
  final expected = package.baseFiles[relativePath];

  if (expected == null) {
    throw ApplyKitException(
      'Package does not contain base file: '
      '$relativePath',
    );
  }

  final file = _safeFile(
    project,
    relativePath,
  );

  if (!await file.exists()) {
    final directory = Directory(
      file.path,
    );

    if (await directory.exists()) {
      return 'Expected file but found directory: '
          '$relativePath';
    }

    return 'Base file is missing: $relativePath';
  }

final current = await file.readAsBytes();

if (!_baseContentMatches(
  current,
  expected,
)) {
  return 'Base file has local changes: '
      '$relativePath';
}

  return null;
}

Future<bool> _pathExists(
  Directory project,
  String relativePath,
) async {
  final file = _safeFile(
    project,
    relativePath,
  );

  if (await file.exists()) {
    return true;
  }

  return Directory(
    file.path,
  ).exists();
}

  Future<void> _applyChanges(
    Directory project,
    FlutterPracticePackage package,
  ) async {
    for (final change in package.changes) {
      switch (change.type) {
        case 'created':
        case 'modified':
          await _writePackageFile(
            project,
            package,
            change.path,
          );
          break;

        case 'deleted':
          await _deletePath(
            project,
            change.path,
          );
          break;

        case 'renamed':
        case 'moved':
          final previousPath = change.previousPath;

          if (previousPath == null) {
            throw ApplyKitException(
              '${change.type} change requires previousPath: '
              '${change.path}',
            );
          }

          await _deletePath(
            project,
            previousPath,
          );

          await _writePackageFile(
            project,
            package,
            change.path,
          );
          break;

        default:
          throw ApplyKitException(
            'Unsupported ApplyKit change type: '
            '${change.type}',
          );
      }
    }
  }

  Future<void> _writePackageFile(
    Directory project,
    FlutterPracticePackage package,
    String relativePath,
  ) async {
    final content = package.files[relativePath];

    if (content == null) {
      throw ApplyKitException(
        'Package does not contain changed file: '
        '$relativePath',
      );
    }

    final destination = _safeFile(
      project,
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
    Directory project,
    String relativePath,
  ) async {
    final file = _safeFile(
      project,
      relativePath,
    );

    if (await file.exists()) {
      await file.delete();

      _log(
        'Deleted: $relativePath',
      );

      return;
    }

    final directory = Directory(
      file.path,
    );

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
    Directory project,
    String relativePath,
  ) {
    if (relativePath.isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.contains('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relativePath)) {
      throw ApplyKitException(
        'Unsafe ApplyKit path: '
        '$relativePath',
      );
    }

    final segments = relativePath.split('/');

    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw ApplyKitException(
        'Unsafe ApplyKit path: '
        '$relativePath',
      );
    }

    final root = p.normalize(
      p.absolute(
        project.path,
      ),
    );

    final destination = p.normalize(
      p.absolute(
        p.joinAll([
          root,
          ...segments,
        ]),
      ),
    );

    if (!p.isWithin(
          root,
          destination,
        ) &&
        destination != root) {
      throw ApplyKitException(
        'ApplyKit path escaped project: '
        '$relativePath',
      );
    }

    return File(
      destination,
    );
  }

  Future<void> _ensureGitRepository(
    Directory project,
  ) async {
    final result = await _processRunner(
      'git',
      const [
        'rev-parse',
        '--is-inside-work-tree',
      ],
      workingDirectory: project.path,
    );

    if (result.exitCode != 0 || '${result.stdout}'.trim() != 'true') {
      throw const ApplyKitException(
        'Current directory is not a Git repository.',
      );
    }
  }

  Future<void> _ensureCleanWorkingTree(
    Directory project,
  ) async {
    final result = await _runGitChecked(
      project,
      const [
        'status',
        '--porcelain',
      ],
      action: 'check Git working tree',
    );

    if ('${result.stdout}'.trim().isNotEmpty) {
      throw const ApplyKitException(
        'Git working tree is not clean. '
        'Commit or stash your changes before applying an ApplyKit package.',
      );
    }
  }

  Future<void> _ensureFlutterProject(
    Directory project,
  ) async {
    final pubspec = File(
      p.join(
        project.path,
        'pubspec.yaml',
      ),
    );

    if (!await pubspec.exists()) {
      throw const ApplyKitException(
        'Current directory is not a Flutter project: '
        'pubspec.yaml is missing.',
      );
    }
  }

  Future<String> _currentBranch(
    Directory project,
  ) async {
    final result = await _runGitChecked(
      project,
      const [
        'branch',
        '--show-current',
      ],
      action: 'read current Git branch',
    );

    final branch = '${result.stdout}'.trim();

    if (branch.isEmpty) {
      throw const ApplyKitException(
        'ApplyKit cannot run from detached HEAD.',
      );
    }

    return branch;
  }

  Future<String> _createUniqueBranchName(
    Directory project,
  ) async {
    final now = DateTime.now();

    final base = 'applykit/'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    var candidate = base;
    var index = 2;

    while (await _branchExists(
      project,
      candidate,
    )) {
      candidate = '$base-$index';

      index++;
    }

    return candidate;
  }

  Future<bool> _branchExists(
    Directory project,
    String branch,
  ) async {
    final result = await _processRunner(
      'git',
      [
        'show-ref',
        '--verify',
        '--quiet',
        'refs/heads/$branch',
      ],
      workingDirectory: project.path,
    );

    return result.exitCode == 0;
  }

  Future<bool> _hasWorkingTreeChanges(
    Directory project,
  ) async {
    final result = await _runGitChecked(
      project,
      const [
        'status',
        '--porcelain',
      ],
      action: 'inspect ApplyKit changes',
    );

    return '${result.stdout}'.trim().isNotEmpty;
  }

  Future<bool> _hasStagedChanges(
  Directory project,
) async {
  final result = await _processRunner(
    'git',
    const [
      'diff',
      '--cached',
      '--quiet',
    ],
    workingDirectory: project.path,
  );

  if (result.exitCode == 0) {
    return false;
  }

  if (result.exitCode == 1) {
    return true;
  }

  throw ApplyKitException(
    'inspect staged ApplyKit changes failed: '
    '${_processDetail(result)}',
  );
}

  Future<void> _tryRestoreBeforeCommitFailure(
    Directory project, {
    required String originalBranch,
    required String branchName,
  }) async {
    await _processRunner(
      'git',
      const [
        'reset',
        '--hard',
        'HEAD',
      ],
      workingDirectory: project.path,
    );

    await _processRunner(
      'git',
      const [
        'clean',
        '-fd',
      ],
      workingDirectory: project.path,
    );

    await _processRunner(
      'git',
      [
        'switch',
        originalBranch,
      ],
      workingDirectory: project.path,
    );

    await _processRunner(
      'git',
      [
        'branch',
        '-D',
        branchName,
      ],
      workingDirectory: project.path,
    );
  }

  Future<ProcessResult> _runGitChecked(
    Directory project,
    List<String> arguments, {
    required String action,
  }) async {
    final result = await _processRunner(
      'git',
      arguments,
      workingDirectory: project.path,
    );

    if (result.exitCode == 0) {
      return result;
    }

    throw ApplyKitException(
      '$action failed: '
      '${_processDetail(result)}',
    );
  }

  String _processDetail(
    ProcessResult result,
  ) {
    final stderrText = '${result.stderr}'.trim();

    final stdoutText = '${result.stdout}'.trim();

    if (stderrText.isNotEmpty) {
      return stderrText;
    }

    if (stdoutText.isNotEmpty) {
      return stdoutText;
    }

    return 'exit code ${result.exitCode}';
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

class ApplyKitException implements Exception {
  const ApplyKitException(
    this.message,
  );

  final String message;

  @override
  String toString() => message;
}

class ApplyKitBaseMismatchException extends ApplyKitException {
  ApplyKitBaseMismatchException(
    List<String> conflicts,
  ) : super(
          'ApplyKit cannot be applied safely because '
          'the target project differs from the package base.\n'
          '${conflicts.map((item) => '- $item').join('\n')}\n'
          'No files were changed.',
        );
}

class ApplyKitMergeConflictException extends ApplyKitException {
  ApplyKitMergeConflictException({
    required this.branchName,
    required this.originalBranch,
    required String detail,
  }) : super(
          'Merge failed or has conflicts.\n'
          'Current branch: $originalBranch\n'
          'ApplyKit branch: $branchName\n'
          '$detail',
        );

  final String branchName;
  final String originalBranch;
}
