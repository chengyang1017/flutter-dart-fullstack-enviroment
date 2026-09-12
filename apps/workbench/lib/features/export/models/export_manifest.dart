import '../../workspace/models/workspace_change.dart';

class ExportManifest {
  const ExportManifest({
    required this.exportedAt,
    required this.changes,
    required this.payloadFiles,
    required this.basePayloadFiles,
    required this.flutterPlatforms,
    this.projectName,
    this.formatVersion = 2,
    this.projectType = 'flutter',
    this.template = 'flutter-playground',
  });

  factory ExportManifest.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawChanges = json['changes'];
    final rawPayloadFiles = json['payloadFiles'];
    final rawBasePayloadFiles =
        json['basePayloadFiles'];
    final rawFlutterPlatforms =
        json['flutterPlatforms'];

    if (rawChanges is! List ||
        rawPayloadFiles is! List ||
        rawBasePayloadFiles is! List ||
        rawFlutterPlatforms is! List) {
      throw const FormatException(
        'Invalid workspace export manifest.',
      );
    }

    return ExportManifest(
      formatVersion:
          json['formatVersion'] as int? ?? 0,
      projectType:
          json['projectType'] as String? ?? '',
      template:
          json['template'] as String? ?? '',
      projectName:
          json['projectName'] as String?,
      exportedAt: DateTime.parse(
        json['exportedAt'] as String,
      ),
      changes: rawChanges.map(
        (raw) {
          final map =
              Map<String, dynamic>.from(
            raw as Map,
          );

          return WorkspaceChange(
            type: WorkspaceChangeType.values
                .byName(
              map['type'] as String,
            ),
            path: map['path'] as String,
            previousPath:
                map['previousPath'] as String?,
          );
        },
      ).toList(growable: false),
      payloadFiles: rawPayloadFiles
          .cast<String>()
          .toList(growable: false),
      basePayloadFiles: rawBasePayloadFiles
          .cast<String>()
          .toList(growable: false),
      flutterPlatforms: rawFlutterPlatforms
          .cast<String>()
          .toList(growable: false),
    );
  }

  final int formatVersion;
  final String projectType;
  final String template;
  final String? projectName;
  final DateTime exportedAt;
  final List<WorkspaceChange> changes;
  final List<String> payloadFiles;
  final List<String> basePayloadFiles;
  final List<String> flutterPlatforms;

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'projectType': projectType,
        'template': template,
        if (projectName != null)
          'projectName': projectName,
        'flutterPlatforms':
            flutterPlatforms,
        'exportedAt':
            exportedAt.toUtc().toIso8601String(),
        'changes': changes
            .map(
              (change) => <String, Object?>{
                'type': change.type.name,
                'path': change.path,
                if (change.previousPath != null)
                  'previousPath':
                      change.previousPath,
              },
            )
            .toList(growable: false),
        'payloadFiles': payloadFiles,
        'basePayloadFiles': basePayloadFiles,
      };
}