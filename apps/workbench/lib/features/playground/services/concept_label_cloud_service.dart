import 'package:http/http.dart' as http;

import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_project.dart';
import '../../workspace/models/workspace_remote_models.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../../workspace/services/http_workspace_remote_persistence.dart';
import '../../workspace/services/workspace_cloud_runtime.dart';
import '../../workspace/services/workspace_project_library.dart';

/// Stores concept-label rules in the authenticated account's cloud Workspace.
///
/// The existing `default-playground` id is intentionally used as a hidden
/// system Workspace. The cloud Workspace adapter already excludes that id from
/// normal project hydration and project lists, so label data stays account-wide
/// without creating a visible project.
class ConceptLabelCloudService {
  ConceptLabelCloudService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const _labelFilePath = '.system/concept-labels.json';
  static const _storageKey = 'concept-label-cloud';

  final http.Client _client;
  final bool _ownsClient;

  bool get available {
    final token = WorkspaceCloudRuntime.accessToken?.trim() ?? '';
    final api = WorkspaceCloudRuntime.apiUrl.trim();
    return WorkspaceCloudRuntime.enabled &&
        WorkspaceCloudRuntime.identity != null &&
        token.isNotEmpty &&
        api.isNotEmpty;
  }

  Future<String?> loadPayload() async {
    final remote = _remoteOrNull();
    if (remote == null) return null;

    final document = await remote.loadWorkspace(
      WorkspaceProjectLibrary.defaultProjectId,
    );
    if (document == null) return null;

    for (final entry in document.snapshot.entries) {
      if (entry.isFile && entry.path == _labelFilePath) {
        return entry.content;
      }
    }
    return null;
  }

  Future<void> savePayload(String payload) async {
    final remote = _remoteOrNull();
    if (remote == null) return;

    final workspaceId = WorkspaceProjectLibrary.defaultProjectId;
    final now = DateTime.now().toUtc();
    var current = await remote.loadWorkspace(workspaceId);

    if (current == null) {
      final project = WorkspaceProject(
        id: workspaceId,
        name: 'Concept Labels',
        storageKey: _storageKey,
        kind: WorkspaceProjectKind.practice,
        lifecycle: WorkspaceLifecycle.saved,
        createdAt: now,
        updatedAt: now,
      );
      await remote.createWorkspace(
        project: project,
        snapshot: _snapshotWithPayload(
          current: null,
          payload: payload,
          savedAt: now,
        ),
      );
      return;
    }

    try {
      await remote.saveWorkspace(
        project: current.project.copyWith(updatedAt: now),
        snapshot: _snapshotWithPayload(
          current: current.snapshot,
          payload: payload,
          savedAt: now,
        ),
        expectedRevision: current.revision,
      );
    } on WorkspaceRevisionConflict {
      current = await remote.loadWorkspace(workspaceId);
      if (current == null) {
        final project = WorkspaceProject(
          id: workspaceId,
          name: 'Concept Labels',
          storageKey: _storageKey,
          kind: WorkspaceProjectKind.practice,
          lifecycle: WorkspaceLifecycle.saved,
          createdAt: now,
          updatedAt: now,
        );
        await remote.createWorkspace(
          project: project,
          snapshot: _snapshotWithPayload(
            current: null,
            payload: payload,
            savedAt: now,
          ),
        );
        return;
      }

      await remote.saveWorkspace(
        project: current.project.copyWith(updatedAt: now),
        snapshot: _snapshotWithPayload(
          current: current.snapshot,
          payload: payload,
          savedAt: now,
        ),
        expectedRevision: current.revision,
      );
    }
  }

  WorkspaceSnapshot _snapshotWithPayload({
    required WorkspaceSnapshot? current,
    required String payload,
    required DateTime savedAt,
  }) {
    WorkspaceEntry? existing;
    if (current != null) {
      for (final entry in current.entries) {
        if (entry.path == _labelFilePath) {
          existing = entry;
          break;
        }
      }
    }

    final labelEntry = WorkspaceEntry(
      id: existing?.id ?? 'concept-label-rules',
      path: _labelFilePath,
      type: WorkspaceEntryType.file,
      content: payload,
    );

    final entries = <WorkspaceEntry>[
      ...?current?.entries.where((entry) => entry.path != _labelFilePath),
      labelEntry,
    ];
    final baseEntries = <WorkspaceEntry>[
      ...?current?.baseEntries.where((entry) => entry.path != _labelFilePath),
      labelEntry,
    ];

    return WorkspaceSnapshot(
      formatVersion:
          current?.formatVersion ?? WorkspaceSnapshot.currentFormatVersion,
      entries: entries,
      baseEntries: baseEntries,
      openFiles: current?.openFiles ?? const <String>[],
      activePath: current?.activePath.isNotEmpty == true
          ? current!.activePath
          : _labelFilePath,
      nextId: current == null
          ? 2
          : existing == null
              ? current.nextId + 1
              : current.nextId,
      savedAt: savedAt,
      expandedDirectoryIds:
          current?.expandedDirectoryIds ?? const <String>[],
      editorStates:
          current?.editorStates ?? const <String, WorkspaceEditorState>{},
    );
  }

  HttpWorkspaceRemotePersistence? _remoteOrNull() {
    if (!available) return null;

    final identity = WorkspaceCloudRuntime.identity;
    final token = WorkspaceCloudRuntime.accessToken?.trim();
    final baseUri = Uri.tryParse(WorkspaceCloudRuntime.apiUrl.trim());
    if (identity == null ||
        token == null ||
        token.isEmpty ||
        baseUri == null ||
        !baseUri.hasScheme) {
      return null;
    }

    return HttpWorkspaceRemotePersistence(
      identity: identity,
      baseUri: baseUri,
      accessToken: token,
      client: _client,
    );
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
