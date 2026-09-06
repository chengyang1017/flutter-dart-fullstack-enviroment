import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../models/run_session.dart';
import '../models/runner_event.dart';
import '../models/runner_preview_target.dart';
import '../models/workspace_runner_source.dart';
import '../services/flutter_runner_client.dart';
import '../services/workspace_runner_source_provider.dart';

class FlutterRunnerController extends ChangeNotifier {
  FlutterRunnerController({
    required this.workspace,
    required this.client,
    WorkspaceRunnerSourceProvider? sourceProvider,
  }) : sourceProvider =
            sourceProvider ?? LocalWorkspaceRunnerSourceProvider(workspace);

  final WorkspaceController workspace;
  final FlutterRunnerClient client;
  final WorkspaceRunnerSourceProvider sourceProvider;

  RunSession? session;
  RunnerStatus status = RunnerStatus.idle;
  RunnerPreviewTarget previewTarget = RunnerPreviewTarget.phone;
  RunnerPreviewOrientation previewOrientation = RunnerPreviewOrientation.portrait;
  final List<String> logs = [];
  String? lastSyncedSourceRevision;

  StreamSubscription<RunnerEvent>? _eventsSubscription;
  bool _disposed = false;

  bool get isMock => client.isMock;
  String get runnerName => client.displayName;
  String? get previewUrl => session?.previewUrl;

  bool get isBusy => const {
        RunnerStatus.creating,
        RunnerStatus.syncing,
        RunnerStatus.starting,
        RunnerStatus.reloading,
        RunnerStatus.restarting,
        RunnerStatus.stopping,
      }.contains(status);

  bool get canRun => !isBusy && status != RunnerStatus.running;
  bool get canHotReload => !isBusy && status == RunnerStatus.running;
  bool get canHotRestart => !isBusy && status == RunnerStatus.running;
  bool get canStop => !isBusy &&
      session != null &&
      status != RunnerStatus.idle &&
      status != RunnerStatus.stopped;

  void selectPreviewTarget(RunnerPreviewTarget target) {
    if (previewTarget == target) return;
    previewTarget = target;
    previewOrientation = RunnerPreviewOrientation.portrait;
    notifyListeners();
  }

  void selectPreviewOrientation(RunnerPreviewOrientation orientation) {
    if (!previewTarget.supportsOrientation || previewOrientation == orientation) {
      return;
    }
    previewOrientation = orientation;
    notifyListeners();
  }

  Future<void> run() async {
    if (!canRun) return;

    try {
      _setStatus(RunnerStatus.syncing);
      final source = await sourceProvider.prepare();
      final currentSession = await _ensureSession(source);
      _setStatus(RunnerStatus.syncing);
      await _syncSource(currentSession.id, source);
      _setStatus(RunnerStatus.starting);
      await client.run(currentSession.id);
    } catch (error) {
      _fail('Run failed', error);
    }
  }

  Future<void> hotReload() async {
    if (!canHotReload || session == null) return;

    try {
      _setStatus(RunnerStatus.syncing);
      final source = await sourceProvider.prepare();
      await _syncSource(session!.id, source);
      _setStatus(RunnerStatus.reloading);
      await client.hotReload(session!.id);
    } catch (error) {
      _fail('Hot reload failed', error);
    }
  }

  Future<void> hotRestart() async {
    if (!canHotRestart || session == null) return;

    try {
      _setStatus(RunnerStatus.syncing);
      final source = await sourceProvider.prepare();
      await _syncSource(session!.id, source);
      _setStatus(RunnerStatus.restarting);
      await client.hotRestart(session!.id);
    } catch (error) {
      _fail('Hot restart failed', error);
    }
  }

  Future<void> stop() async {
    if (!canStop || session == null) return;

    try {
      _setStatus(RunnerStatus.stopping);
      await client.stop(session!.id);
    } catch (error) {
      _fail('Stop failed', error);
    }
  }

  void clearConsole() {
    if (logs.isEmpty) return;
    logs.clear();
    notifyListeners();
  }

  Future<RunSession> _ensureSession(WorkspaceRunnerSource source) async {
    final current = session;
    if (current != null) return current;

    _setStatus(RunnerStatus.creating);
    _appendLog('Creating ${client.displayName} session...');

    final created = await client.createSession(
      files: source.files,
      firebaseCapabilities: source.firebaseCapabilities,
    );
    session = created;
    _setStatus(created.status);

    await _eventsSubscription?.cancel();
    _eventsSubscription = client
        .watchSession(created.id)
        .listen(_handleEvent, onError: (Object error) {
      _fail('Runner event stream failed', error);
    });

    _appendLog('Runner session ready: ${created.id}');
    return created;
  }

  Future<void> _syncSource(
    String sessionId,
    WorkspaceRunnerSource source,
  ) async {
    await client.syncWorkspace(
      sessionId: sessionId,
      files: source.files,
      changes: source.changes,
      firebaseCapabilities: source.firebaseCapabilities,
    );
    lastSyncedSourceRevision = source.remoteRevision;
    final revision = source.remoteRevision;
    if (revision != null) {
      _appendLog('Synced persisted Workspace revision $revision to Runner.');
    }
  }

  void _handleEvent(RunnerEvent event) {
    if (_disposed) return;

    switch (event.type) {
      case RunnerEventType.status:
        final nextStatus = event.status;
        if (nextStatus != null) {
          _setStatus(nextStatus);
        }
        break;
      case RunnerEventType.log:
        final message = event.message;
        if (message != null) {
          _appendLog(message);
        }
        break;
      case RunnerEventType.session:
        final nextSession = event.session;
        if (nextSession != null) {
          session = nextSession;
          status = nextSession.status;
          notifyListeners();
        }
        break;
    }
  }

  void _setStatus(RunnerStatus value) {
    status = value;
    final current = session;
    if (current != null) {
      session = current.copyWith(
        status: value,
        lastActivityAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  void _appendLog(String message) {
    logs.add(message);
    notifyListeners();
  }

  void _fail(String action, Object error) {
    status = RunnerStatus.error;
    final current = session;
    if (current != null) {
      session = current.copyWith(
        status: RunnerStatus.error,
        lastActivityAt: DateTime.now(),
      );
    }
    logs.add('$action: $error');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_eventsSubscription?.cancel());
    final current = session;
    if (current != null) {
      unawaited(client.disposeSession(current.id));
    }
    super.dispose();
  }
}
