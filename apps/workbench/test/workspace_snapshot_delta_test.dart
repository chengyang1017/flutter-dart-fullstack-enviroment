import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_entry.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_snapshot_delta.dart';

void main() {
  test('delta only carries changed file payloads plus small manifest', () {
    final previous = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'file-main',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: 'void main() {}\n',
        ),
        WorkspaceEntry(
          id: 'file-other',
          path: 'lib/other.dart',
          type: WorkspaceEntryType.file,
          content: 'const value = 1;\n',
        ),
      ],
      baseEntries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'file-main',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: 'void main() {}\n',
        ),
        WorkspaceEntry(
          id: 'file-other',
          path: 'lib/other.dart',
          type: WorkspaceEntryType.file,
          content: 'const value = 1;\n',
        ),
      ],
      openFiles: const <String>['lib/main.dart'],
      activePath: 'lib/main.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 1),
    );

    final current = WorkspaceSnapshot(
      entries: const <WorkspaceEntry>[
        WorkspaceEntry(
          id: 'file-main',
          path: 'lib/main.dart',
          type: WorkspaceEntryType.file,
          content: 'void main() { print("changed"); }\n',
        ),
        WorkspaceEntry(
          id: 'file-other',
          path: 'lib/other.dart',
          type: WorkspaceEntryType.file,
          content: 'const value = 1;\n',
        ),
      ],
      baseEntries: previous.baseEntries,
      openFiles: const <String>['lib/main.dart'],
      activePath: 'lib/main.dart',
      nextId: 3,
      savedAt: DateTime.utc(2026, 9, 9, 1, 0, 1),
    );

    final delta = WorkspaceSnapshotDelta.between(previous, current);

    expect(delta.entryUpserts, hasLength(1));
    expect(delta.entryUpserts.single.id, 'file-main');
    expect(delta.baseEntryUpserts, isEmpty);
    expect(delta.entryDeletes, isEmpty);
    expect(delta.baseEntryDeletes, isEmpty);

    final json = delta.toJson();
    final entries = json['entries'] as Map<String, dynamic>;
    final upserts = entries['upsert'] as List<dynamic>;
    expect(upserts, hasLength(1));
    expect((upserts.single as Map)['id'], 'file-main');
  });
}
