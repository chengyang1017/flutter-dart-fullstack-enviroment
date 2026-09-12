import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_capability.dart';
import 'package:flutter_ui_playground/features/workspace/models/workspace_project.dart';

void main() {
  test('WorkspaceProject persists Firebase capabilities independently', () {
    final now = DateTime.utc(2026, 9, 3);
    final project = WorkspaceProject(
      id: 'workspace-a',
      name: 'Firebase + Serverpod',
      storageKey: 'workspace:workspace-a',
      kind: WorkspaceProjectKind.practice,
      lifecycle: WorkspaceLifecycle.saved,
      createdAt: now,
      updatedAt: now,
      firebaseCapabilities: const <FirebaseCapability>{
        FirebaseCapability.auth,
        FirebaseCapability.firestore,
        FirebaseCapability.functions,
      },
    );

    final json = project.toJson();
    expect(
      json['firebaseCapabilities'],
      ['auth', 'firestore', 'functions'],
    );

    final restored = WorkspaceProject.fromJson(json);
    expect(
      restored.firebaseCapabilities,
      {
        FirebaseCapability.auth,
        FirebaseCapability.firestore,
        FirebaseCapability.functions,
      },
    );
  });

  test('older Workspace metadata remains compatible without capabilities', () {
    final restored = WorkspaceProject.fromJson(<String, dynamic>{
      'id': 'legacy',
      'name': 'Legacy',
      'storageKey': 'workspace:legacy',
      'kind': 'practice',
      'lifecycle': 'saved',
      'createdAt': '2026-09-03T00:00:00.000Z',
      'updatedAt': '2026-09-03T00:00:00.000Z',
    });

    expect(restored.firebaseCapabilities, isEmpty);
  });

  test('Firebase capabilities map to additive Flutter packages', () {
    final packages = firebaseFlutterPackages(const <FirebaseCapability>{
      FirebaseCapability.auth,
      FirebaseCapability.storage,
    });

    expect(
      packages,
      {
        'firebase_core',
        'firebase_auth',
        'firebase_storage',
      },
    );
    expect(
      firebaseFlutterPackages(const <FirebaseCapability>{}),
      isEmpty,
    );
  });
}
