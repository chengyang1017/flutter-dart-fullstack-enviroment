import 'dart:io';
import 'dart:math';

class RunnerLogEntry {
  const RunnerLogEntry({
    required this.index,
    required this.message,
  });

  final int index;
  final String message;

  Map<String, Object?> toJson() => {
        'index': index,
        'message': message,
      };
}

class RunnerSession {
  RunnerSession({
    required this.id,
    required this.directory,
    required this.createdAt,
  })  : publicAccessKey = _createPublicAccessKey(),
        lastActivityAt = createdAt;

  final String id;
  final Directory directory;
  final DateTime createdAt;
  final String publicAccessKey;
  DateTime lastActivityAt;

  String projectType = 'flutter';
  String status = 'creating';
  String? previewUrl;
  String? backendUrl;
  Process? process;
  Process? backendProcess;

  final Set<String> firebaseCapabilities = <String>{};

  // Runtime-specific state is intentionally not serialized to clients.
  // Local execution does not need these fields; the Docker backend uses them
  // for its container id/name and host ports mapped to the two dev servers.
  String? runtimeId;
  int? runtimePreviewPort;
  int? runtimeBackendPort;

  // Host ports exposed only through the public runtime gateway.
  int? previewGatewayPort;
  int? backendGatewayPort;

  // Database runtime state is also private to the runner. A Serverpod session
  // only receives these values when its workspace contains a persisted model.
  String? runtimeNetworkId;
  String? databaseRuntimeId;
  String? databasePassword;

  final List<RunnerLogEntry> logs = <RunnerLogEntry>[];
  final Set<String> managedFiles = <String>{};

  static String _createPublicAccessKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  void setStatus(String value) {
    status = value;
    touch();
  }

  void setFirebaseCapabilities(Iterable<String> values) {
    firebaseCapabilities
      ..clear()
      ..addAll(values);
    touch();
  }

  void touch() {
    lastActivityAt = DateTime.now().toUtc();
  }

  void addLog(String message) {
    final trimmed = message.trimRight();
    if (trimmed.isEmpty) return;
    logs.add(
      RunnerLogEntry(
        index: logs.length,
        message: trimmed,
      ),
    );
    touch();
  }

  Map<String, Object?> toJson() {
    final capabilities = firebaseCapabilities.toList()..sort();
    return {
      'id': id,
      'projectType': projectType,
      'status': status,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'lastActivityAt': lastActivityAt.toUtc().toIso8601String(),
      'firebaseCapabilities': capabilities,
      'previewUrl': previewUrl,
      'backendUrl': backendUrl,
    };
  }
}
