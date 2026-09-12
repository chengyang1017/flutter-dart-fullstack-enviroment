import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/concept/services/concept_project_projection_service.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';

void main() {
  const service = ConceptProjectProjectionService();

  test('detects Glyphora-style Flutter app inside a mixed monorepo', () {
    final snapshot = _glyphoraRepositorySnapshot();

    final candidates = service.detectFlutterProjects(snapshot);

    expect(candidates, hasLength(1));
    expect(candidates.single.projectRoot, 'apps/mobile-flutter');
    expect(candidates.single.projectName, 'glyphora_mobile');
  });

  test('projects selected Flutter app to a normal concept workspace root', () {
    final repository = _glyphoraRepositorySnapshot();
    final candidate = service.detectFlutterProjects(repository).single;

    final projection = service.project(
      repositorySnapshot: repository,
      repositoryName: 'chengyang1017/glyphora',
      candidate: candidate,
    );

    expect(projection.context.isMonorepoProject, isTrue);
    expect(projection.context.projectRoot, 'apps/mobile-flutter');
    expect(
      projection.context.sourceLabel,
      'chengyang1017/glyphora / apps/mobile-flutter',
    );

    final paths = projection.snapshot.entries.map((entry) => entry.path).toSet();
    expect(paths, contains('lib'));
    expect(paths, contains('lib/main.dart'));
    expect(paths, contains('lib/features/feed.dart'));
    expect(paths, contains('assets'));
    expect(paths, contains('assets/logo.png'));
    expect(paths, contains('pubspec.yaml'));
    expect(paths, contains('android'));

    expect(paths.any((path) => path.startsWith('apps/')), isFalse);
    expect(paths.contains('apps/api/package.json'), isFalse);
    expect(paths.contains('apps/mobile-rn/package.json'), isFalse);

    final asset = projection.snapshot.entries.singleWhere(
      (entry) => entry.path == 'assets/logo.png',
    );
    expect(asset.isBinary, isTrue);
    expect(asset.bytes, <int>[0, 1, 2, 255]);
    expect(projection.snapshot.activePath, 'lib/main.dart');
  });

  test('maps concept paths back to the original monorepo project root', () {
    final repository = _glyphoraRepositorySnapshot();
    final candidate = service.detectFlutterProjects(repository).single;
    final projection = service.project(
      repositorySnapshot: repository,
      repositoryName: 'chengyang1017/glyphora',
      candidate: candidate,
    );

    expect(
      projection.context.toRepositoryPath('lib/main.dart'),
      'apps/mobile-flutter/lib/main.dart',
    );
    expect(
      projection.context.toRepositoryPath('assets/logo.png'),
      'apps/mobile-flutter/assets/logo.png',
    );
    expect(
      projection.context.toConceptPath('apps/mobile-flutter/pubspec.yaml'),
      'pubspec.yaml',
    );
    expect(projection.context.toConceptPath('apps/api/index.ts'), isNull);
  });

  test('multiple Flutter apps stay explicit instead of choosing the wrong one', () {
    final base = _glyphoraRepositorySnapshot();
    final entries = <WorkspaceEntry>[
      ...base.entries,
      const WorkspaceEntry(
        id: 'dir-second',
        path: 'apps/second-flutter',
        type: WorkspaceEntryType.directory,
      ),
      const WorkspaceEntry(
        id: 'dir-second-lib',
        path: 'apps/second-flutter/lib',
        type: WorkspaceEntryType.directory,
      ),
      const WorkspaceEntry(
        id: 'file-second-main',
        path: 'apps/second-flutter/lib/main.dart',
        type: WorkspaceEntryType.file,
        content: 'void main() {}',
      ),
      const WorkspaceEntry(
        id: 'file-second-pubspec',
        path: 'apps/second-flutter/pubspec.yaml',
        type: WorkspaceEntryType.file,
        content: '''name: second_app\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n''',
      ),
    ];
    final snapshot = WorkspaceSnapshot(
      entries: entries,
      baseEntries: entries,
      openFiles: const <String>['apps/mobile-flutter/lib/main.dart'],
      activePath: 'apps/mobile-flutter/lib/main.dart',
      nextId: 100,
      savedAt: DateTime.utc(2026, 9, 8),
    );

    final candidates = service.detectFlutterProjects(snapshot);
    expect(candidates, hasLength(2));
    expect(
      candidates.map((candidate) => candidate.projectRoot),
      containsAll(<String>[
        'apps/mobile-flutter',
        'apps/second-flutter',
      ]),
    );
    expect(
      () => service.projectSingle(
        repositorySnapshot: snapshot,
        repositoryName: 'team/monorepo',
      ),
      throwsFormatException,
    );
  });
}

WorkspaceSnapshot _glyphoraRepositorySnapshot() {
  final entries = <WorkspaceEntry>[
    const WorkspaceEntry(
      id: 'dir-apps',
      path: 'apps',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'dir-api',
      path: 'apps/api',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'file-api-package',
      path: 'apps/api/package.json',
      type: WorkspaceEntryType.file,
      content: '{"name":"glyphora-api"}',
    ),
    const WorkspaceEntry(
      id: 'dir-rn',
      path: 'apps/mobile-rn',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'file-rn-package',
      path: 'apps/mobile-rn/package.json',
      type: WorkspaceEntryType.file,
      content: '{"name":"glyphora-rn"}',
    ),
    const WorkspaceEntry(
      id: 'dir-flutter',
      path: 'apps/mobile-flutter',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'dir-flutter-lib',
      path: 'apps/mobile-flutter/lib',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'dir-flutter-features',
      path: 'apps/mobile-flutter/lib/features',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'file-flutter-main',
      path: 'apps/mobile-flutter/lib/main.dart',
      type: WorkspaceEntryType.file,
      content: 'void main() {}',
    ),
    const WorkspaceEntry(
      id: 'file-flutter-feed',
      path: 'apps/mobile-flutter/lib/features/feed.dart',
      type: WorkspaceEntryType.file,
      content: 'class Feed {}',
    ),
    const WorkspaceEntry(
      id: 'file-flutter-pubspec',
      path: 'apps/mobile-flutter/pubspec.yaml',
      type: WorkspaceEntryType.file,
      content: '''name: glyphora_mobile\ndependencies:\n  flutter:\n    sdk: flutter\nflutter:\n  uses-material-design: true\n  assets:\n    - assets/\n''',
    ),
    const WorkspaceEntry(
      id: 'dir-flutter-assets',
      path: 'apps/mobile-flutter/assets',
      type: WorkspaceEntryType.directory,
    ),
    WorkspaceEntry.binary(
      id: 'file-logo',
      path: 'apps/mobile-flutter/assets/logo.png',
      bytes: const <int>[0, 1, 2, 255],
    ),
    const WorkspaceEntry(
      id: 'dir-flutter-android',
      path: 'apps/mobile-flutter/android',
      type: WorkspaceEntryType.directory,
    ),
    const WorkspaceEntry(
      id: 'file-flutter-gradle',
      path: 'apps/mobile-flutter/android/build.gradle.kts',
      type: WorkspaceEntryType.file,
      content: '// android config',
    ),
  ];

  return WorkspaceSnapshot(
    entries: entries,
    baseEntries: entries,
    openFiles: const <String>[
      'apps/mobile-flutter/lib/main.dart',
      'apps/api/package.json',
    ],
    activePath: 'apps/api/package.json',
    nextId: 50,
    savedAt: DateTime.utc(2026, 9, 8),
  );
}
