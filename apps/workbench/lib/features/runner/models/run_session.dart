import '../../workspace/models/workspace_capability.dart';

enum RunnerStatus {
  idle,
  creating,
  ready,
  syncing,
  starting,
  running,
  reloading,
  restarting,
  stopping,
  stopped,
  error,
}

extension RunnerStatusLabel on RunnerStatus {
  String get label => switch (this) {
        RunnerStatus.idle => 'Idle',
        RunnerStatus.creating => 'Creating',
        RunnerStatus.ready => 'Ready',
        RunnerStatus.syncing => 'Syncing',
        RunnerStatus.starting => 'Starting',
        RunnerStatus.running => 'Running',
        RunnerStatus.reloading => 'Hot Reload',
        RunnerStatus.restarting => 'Hot Restart',
        RunnerStatus.stopping => 'Stopping',
        RunnerStatus.stopped => 'Stopped',
        RunnerStatus.error => 'Error',
      };

  static RunnerStatus parse(String value) {
    for (final status in RunnerStatus.values) {
      if (status.name == value) return status;
    }
    throw FormatException('Unknown runner status: $value');
  }
}

class RunSession {
  const RunSession({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.lastActivityAt,
    this.projectType = 'flutter',
    this.firebaseCapabilities = const <FirebaseCapability>{},
    this.previewUrl,
    this.backendUrl,
  });

  factory RunSession.fromJson(Map<String, dynamic> json) {
    return RunSession(
      id: json['id'] as String,
      projectType: json['projectType'] as String? ?? 'flutter',
      status: RunnerStatusLabel.parse(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActivityAt: DateTime.parse(json['lastActivityAt'] as String),
      firebaseCapabilities: FirebaseCapabilityCodec.decode(
        json['firebaseCapabilities'],
      ),
      previewUrl: json['previewUrl'] as String?,
      backendUrl: json['backendUrl'] as String?,
    );
  }

  final String id;
  final String projectType;
  final RunnerStatus status;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final Set<FirebaseCapability> firebaseCapabilities;
  final String? previewUrl;
  final String? backendUrl;

  Map<String, Object?> toJson() => {
        'id': id,
        'projectType': projectType,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastActivityAt': lastActivityAt.toUtc().toIso8601String(),
        'firebaseCapabilities': FirebaseCapabilityCodec.encode(
          firebaseCapabilities,
        ),
        'previewUrl': previewUrl,
        'backendUrl': backendUrl,
      };

  RunSession copyWith({
    RunnerStatus? status,
    DateTime? lastActivityAt,
    Set<FirebaseCapability>? firebaseCapabilities,
    String? previewUrl,
    bool clearPreviewUrl = false,
    String? backendUrl,
    bool clearBackendUrl = false,
  }) {
    return RunSession(
      id: id,
      projectType: projectType,
      status: status ?? this.status,
      createdAt: createdAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      firebaseCapabilities: firebaseCapabilities ?? this.firebaseCapabilities,
      previewUrl: clearPreviewUrl ? null : previewUrl ?? this.previewUrl,
      backendUrl: clearBackendUrl ? null : backendUrl ?? this.backendUrl,
    );
  }
}
