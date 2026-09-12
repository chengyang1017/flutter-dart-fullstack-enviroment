import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class FlutterPracticePackage {
  const FlutterPracticePackage({
    required this.formatVersion,
    required this.projectType,
    required this.template,
    required this.projectName,
    required this.flutterPlatforms,
    required this.files,
    required this.baseFiles,
    required this.changes,
  });

  final int formatVersion;
  final String projectType;
  final String template;
  final String projectName;
  final List<String> flutterPlatforms;

  final Map<String, Uint8List> files;
  final Map<String, Uint8List> baseFiles;

  final List<FlutterPracticeChange> changes;

  static const supportedProjectTypes = <String>{
    'flutter',
    'flutter-dart-frog',
    'flutter-serverpod-mini',
  };

  static const supportedFlutterPlatforms = <String>{
    'android',
    'ios',
    'web',
    'windows',
    'macos',
    'linux',
  };

  factory FlutterPracticePackage.decode(
    Uint8List bytes,
  ) {
    final Archive archive;

    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        'Unable to read .applykit package.',
      );
    }

    final manifests = archive.files.where(
      (file) =>
          file.isFile &&
          file.name == 'manifest.json',
    );

    if (manifests.length != 1) {
      throw const FormatException(
        'Package must contain exactly one manifest.json.',
      );
    }

    final manifestValue = jsonDecode(
      utf8.decode(
        _bytesOf(manifests.single),
        allowMalformed: false,
      ),
    );

    if (manifestValue is! Map) {
      throw const FormatException(
        'manifest.json must be a JSON object.',
      );
    }

    final manifest = Map<String, dynamic>.from(
      manifestValue,
    );

    final formatVersion =
        manifest['formatVersion'];

    final projectType =
        manifest['projectType'];

    final template =
        manifest['template'];

    final rawProjectName =
        manifest['projectName'];

    final rawFlutterPlatforms =
        manifest['flutterPlatforms'];

    final rawPayloadFiles =
        manifest['payloadFiles'];

    final rawBasePayloadFiles =
        manifest['basePayloadFiles'];

    final rawChanges =
        manifest['changes'];

    if (formatVersion != 2) {
      throw FormatException(
        'Unsupported .applykit format version: '
        '$formatVersion',
      );
    }

    if (projectType is! String ||
        !supportedProjectTypes.contains(
          projectType,
        )) {
      throw FormatException(
        'Unsupported project type: '
        '$projectType',
      );
    }

    if (template != 'flutter-playground') {
      throw const FormatException(
        'Package does not use the supported Flutter workspace template.',
      );
    }

    if (rawProjectName is! String ||
        !RegExp(
          r'^[a-z][a-z0-9_]*$',
        ).hasMatch(rawProjectName)) {
      throw const FormatException(
        'manifest projectName is missing or invalid.',
      );
    }

    if (rawFlutterPlatforms is! List ||
        rawFlutterPlatforms.isEmpty ||
        rawFlutterPlatforms.any(
          (value) => value is! String,
        )) {
      throw const FormatException(
        'manifest flutterPlatforms must contain at least one platform.',
      );
    }

    final flutterPlatforms =
        rawFlutterPlatforms
            .cast<String>()
            .toList(growable: false);

    if (flutterPlatforms.toSet().length !=
        flutterPlatforms.length) {
      throw const FormatException(
        'manifest flutterPlatforms contains duplicates.',
      );
    }

    for (final platform in flutterPlatforms) {
      if (!supportedFlutterPlatforms.contains(
        platform,
      )) {
        throw FormatException(
          'Unsupported Flutter platform: '
          '$platform',
        );
      }
    }

    if (rawPayloadFiles is! List ||
        rawPayloadFiles.any(
          (value) => value is! String,
        )) {
      throw const FormatException(
        'manifest payloadFiles must be a list of strings.',
      );
    }

    if (rawBasePayloadFiles is! List ||
        rawBasePayloadFiles.any(
          (value) => value is! String,
        )) {
      throw const FormatException(
        'manifest basePayloadFiles must be a list of strings.',
      );
    }

    if (rawChanges is! List) {
      throw const FormatException(
        'manifest changes must be a list.',
      );
    }

    final payloadFiles =
        rawPayloadFiles.cast<String>();

    final basePayloadFiles =
        rawBasePayloadFiles.cast<String>();

    if (payloadFiles.toSet().length !=
        payloadFiles.length) {
      throw const FormatException(
        'manifest payloadFiles contains duplicates.',
      );
    }

    if (basePayloadFiles.toSet().length !=
        basePayloadFiles.length) {
      throw const FormatException(
        'manifest basePayloadFiles contains duplicates.',
      );
    }

    final changes = rawChanges.map(
      (raw) {
        if (raw is! Map) {
          throw const FormatException(
            'Every manifest change must be an object.',
          );
        }

        final map = Map<String, dynamic>.from(
          raw,
        );

        final type = map['type'];
        final path = map['path'];
        final previousPath =
            map['previousPath'];

        if (type is! String ||
            path is! String) {
          throw const FormatException(
            'Invalid manifest change.',
          );
        }

        if (!const {
          'created',
          'modified',
          'deleted',
          'renamed',
          'moved',
        }.contains(type)) {
          throw FormatException(
            'Unsupported change type: $type',
          );
        }

        if (previousPath != null &&
            previousPath is! String) {
          throw const FormatException(
            'Invalid previousPath.',
          );
        }

        _validatePortablePath(path);

        if (previousPath is String) {
          _validatePortablePath(
            previousPath,
          );
        }

        return FlutterPracticeChange(
          type: type,
          path: path,
          previousPath:
              previousPath as String?,
        );
      },
    ).toList(growable: false);

    final files = <String, Uint8List>{};

    for (final path in payloadFiles) {
      _validatePortablePath(path);

      final matches = archive.files.where(
        (file) =>
            file.isFile &&
            file.name == path,
      );

      if (matches.length != 1) {
        throw FormatException(
          'Missing or duplicate payload file: '
          '$path',
        );
      }

      files[path] = Uint8List.fromList(
        _bytesOf(matches.single),
      );
    }

    final baseFiles = <String, Uint8List>{};

    for (final path in basePayloadFiles) {
      _validatePortablePath(path);

      final archivePath =
          '.applykit/base/$path';

      final matches = archive.files.where(
        (file) =>
            file.isFile &&
            file.name == archivePath,
      );

      if (matches.length != 1) {
        throw FormatException(
          'Missing or duplicate base payload file: '
          '$path',
        );
      }

      baseFiles[path] = Uint8List.fromList(
        _bytesOf(matches.single),
      );
    }

    return FlutterPracticePackage(
      formatVersion: formatVersion,
      projectType: projectType,
      template: template as String,
      projectName: rawProjectName,
      flutterPlatforms:
          List<String>.unmodifiable(
        flutterPlatforms,
      ),
      files: Map<String, Uint8List>.unmodifiable(
        files,
      ),
      baseFiles:
          Map<String, Uint8List>.unmodifiable(
        baseFiles,
      ),
      changes:
          List<FlutterPracticeChange>.unmodifiable(
        changes,
      ),
    );
  }

  static void _validatePortablePath(
    String path,
  ) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\')) {
      throw FormatException(
        'Invalid ApplyKit path: $path',
      );
    }

    if (RegExp(
      r'^[A-Za-z]:',
    ).hasMatch(path)) {
      throw FormatException(
        'Absolute paths are not allowed: '
        '$path',
      );
    }

    final segments = path.split('/');

    if (segments.any(
      (segment) =>
          segment.isEmpty ||
          segment == '.' ||
          segment == '..',
    )) {
      throw FormatException(
        'Unsafe ApplyKit path: $path',
      );
    }

    const forbiddenRoots = <String>{
      '.dart_tool',
      '.git',
      '.gradle',
      '.idea',
      'build',
      'coverage',
    };

    if (forbiddenRoots.contains(
      segments.first,
    )) {
      throw FormatException(
        'Runtime/generated path is not allowed: '
        '$path',
      );
    }
  }

  static List<int> _bytesOf(
    ArchiveFile file,
  ) =>
      file.content;
}

class FlutterPracticeChange {
  const FlutterPracticeChange({
    required this.type,
    required this.path,
    this.previousPath,
  });

  final String type;
  final String path;
  final String? previousPath;
}