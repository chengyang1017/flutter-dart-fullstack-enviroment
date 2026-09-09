import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../workspace/controllers/workspace_controller.dart';
import '../models/run_session.dart';
import '../models/runner_event.dart';
import '../models/runner_preview_target.dart';
import '../models/runner_pub_get_result.dart';
import '../models/workspace_runner_source.dart';
import '../services/flutter_runner_client.dart';
import '../services/http_flutter_runner_client.dart';
import '../services/workspace_runner_source_provider.dart';

class FlutterRunnerController extends ChangeNotifier {
  FlutterRunnerController({
    required this.workspace,
    required this.client,
    WorkspaceRunnerSourceProvider? sourceProvider,
  }) : sourceProvider =
            sourceProvider ?? LocalWorkspaceRunnerSourceProvider(workspace) {
    activeInstance = this;
  }

  /// The playground owns one active Runner controller at a time. The package
  /// manager button in the Workspace project bar uses this to target the
  /// currently selected project without introducing a second Workspace state.
  static FlutterRunnerController? activeInstance;

  final WorkspaceController workspace;
  final FlutterRunnerClient client;
  final WorkspaceRunnerSourceProvider sourceProvider;

  RunSession? session;
  RunnerStatus status = RunnerStatus.idle;
  RunnerPreviewTarget previewTarget = RunnerPreviewTarget.phone;
  RunnerPreviewOrientation previewOrientation =
      RunnerPreviewOrientation.portrait;
  final List<String> logs = [];
  String? lastSyncedSourceRevision;
  RunnerPubGetResult? lastPubGetResult;

  StreamSubscription<RunnerEvent>? _eventsSubscription;
  bool _disposed = false;
  String? _lastPubGetPubspec;

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
  bool get canPubGet =>
      client is FlutterPackageRunnerClient &&
      !isBusy &&
      status != RunnerStatus.running;
  bool get canStop =>
      !isBusy &&
      session != null &&
      status != RunnerStatus.idle &&
      status != RunnerStatus.stopped;
  bool get canRunTerminalCommand =>
      client is HttpFlutterRunnerClient && !isBusy;

  bool get isPubGetVerifiedForCurrentPubspec {
    final current = _currentPubspecContent();
    return current != null && _lastPubGetPubspec == current;
  }

  void selectPreviewTarget(RunnerPreviewTarget target) {
    if (previewTarget == target) return;
    previewTarget = target;
    previewOrientation = RunnerPreviewOrientation.portrait;
    notifyListeners();
  }

  void selectPreviewOrientation(RunnerPreviewOrientation orientation) {
    if (!previewTarget.supportsOrientation ||
        previewOrientation == orientation) {
      return;
    }
    previewOrientation = orientation;
    notifyListeners();
  }

  Future<RunnerPubGetResult> pubGet() async {
    if (client is! FlutterPackageRunnerClient) {
      throw StateError('当前 Runner 不支持独立 Pub Get。');
    }
    final packageClient = client as FlutterPackageRunnerClient;

    if (!canPubGet) {
      throw StateError(
        status == RunnerStatus.running
            ? '请先停止正在运行的 App，再执行 Pub Get。'
            : 'Runner 正忙，请稍后再执行 Pub Get。',
      );
    }

    final restoreStopped = status == RunnerStatus.stopped;

    try {
      _setStatus(RunnerStatus.syncing);
      final source = await sourceProvider.prepare();
      final currentSession = await _ensureSession(source);
      _setStatus(RunnerStatus.syncing);
      await _syncSource(currentSession.id, source);
      _appendLog('Resolving Flutter packages...');

      final result = await packageClient.pubGet(currentSession.id);
      lastPubGetResult = result;
      _lastPubGetPubspec = _currentPubspecContent();
      _storeLockFile(result.lockFile);

      _setStatus(
        restoreStopped ? RunnerStatus.stopped : RunnerStatus.ready,
      );
      _appendLog('flutter pub get completed.');
      return result;
    } catch (error) {
      _fail('Pub get failed', error);
      rethrow;
    }
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
      _lastPubGetPubspec = _currentPubspecContent();
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

  Future<void> runTerminalCommand(String command) async {
    final normalized = command.trim();
    if (normalized.isEmpty) return;

    final terminalClient = client;
    if (terminalClient is! HttpFlutterRunnerClient) {
      throw StateError('当前 Runner 不支持终端命令。');
    }

    _appendLog('> $normalized');

    try {
      var currentSession = session;
      if (currentSession == null) {
        final source = await sourceProvider.prepare();
        currentSession = await _ensureSession(source);
        await _syncSource(currentSession.id, source);
      } else if (status != RunnerStatus.running) {
        final source = await sourceProvider.prepare();
        await _syncSource(currentSession.id, source);
      }

      final response = await http.post(
        Uri.parse(
          '${terminalClient.baseUrl}/sessions/${currentSession.id}/command',
        ),
        headers: <String, String>{
          'accept': 'application/json',
          'content-type': 'application/json',
          if (terminalClient.accessToken.trim().isNotEmpty)
            'authorization': 'Bearer ${terminalClient.accessToken.trim()}',
        },
        body: jsonEncode(<String, Object?>{'command': normalized}),
      );

      if (response.statusCode != 200) {
        var detail = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['error'] is String) {
            detail = decoded['error'] as String;
          }
        } catch (_) {}
        throw StateError('Terminal command failed: $detail');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['exitCode'] is! num) {
        throw const FormatException(
          'Runner terminal response is missing exitCode.',
        );
      }
      final exitCode = (decoded['exitCode'] as num).toInt();
      _appendLog('[terminal] exited with code $exitCode');
    } catch (error) {
      _appendLog('[terminal] command failed: $error');
      rethrow;
    }
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
    _eventsSubscription = client.watchSession(created.id).listen(
      _handleEvent,
      onError: (Object error) {
        _fail('Runner event stream failed', error);
      },
    );

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

  String? _currentPubspecContent() {
    final entry = workspace.entryAt('pubspec.yaml');
    if (entry == null || !entry.isFile || !entry.isText) return null;
    return entry.content;
  }

  void _storeLockFile(String? content) {
    if (content == null || content.trim().isEmpty) return;

    final existing = workspace.entryAt('pubspec.lock');
    if (existing != null && existing.isFile) {
      workspace.updateFileContent('pubspec.lock', content);
      return;
    }

    final previousPath = workspace.activePath;
    workspace.createFile('', 'pubspec.lock', content: content);

    if (previousPath.isNotEmpty && workspace.entryAt(previousPath) != null) {
      workspace.openFile(previousPath);
      workspace.closeFile('pubspec.lock');
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
    if (identical(activeInstance, this)) {
      activeInstance = null;
    }
    unawaited(_eventsSubscription?.cancel());
    final current = session;
    if (current != null) {
      unawaited(client.disposeSession(current.id));
    }
    super.dispose();
  }
}
