import 'package:yaml/yaml.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../models/package_models.dart';

class PubspecPackageService {
  const PubspecPackageService();

  List<PackageDependencyInfo> read(WorkspaceController workspace) {
    final pubspec = _pubspecContent(workspace);
    final root = loadYaml(pubspec);
    if (root is! YamlMap) {
      throw const FormatException('pubspec.yaml root must be a map.');
    }

    final lockVersions = _readLockVersions(workspace);
    final result = <PackageDependencyInfo>[];
    _readSection(
      root['dependencies'],
      PackageDependencyGroup.dependencies,
      lockVersions,
      result,
    );
    _readSection(
      root['dev_dependencies'],
      PackageDependencyGroup.devDependencies,
      lockVersions,
      result,
    );

    result.sort((a, b) {
      final group = a.group.index.compareTo(b.group.index);
      return group != 0 ? group : a.name.compareTo(b.name);
    });
    return result;
  }

  void upsertHostedDependency(
    WorkspaceController workspace, {
    required String packageName,
    required String version,
    required PackageDependencyGroup group,
    required bool compatibleRange,
  }) {
    _validatePackageName(packageName);
    var source = _pubspecContent(workspace);
    source = _removeEntry(
      source,
      PackageDependencyGroup.dependencies.yamlKey,
      packageName,
    );
    source = _removeEntry(
      source,
      PackageDependencyGroup.devDependencies.yamlKey,
      packageName,
    );
    source = _insertEntry(
      source,
      group.yamlKey,
      packageName,
      compatibleRange ? '^$version' : version,
    );
    workspace.updateFileContent('pubspec.yaml', source);
  }

  void removeDependency(
    WorkspaceController workspace, {
    required String packageName,
    required PackageDependencyGroup group,
  }) {
    final source = _removeEntry(
      _pubspecContent(workspace),
      group.yamlKey,
      packageName,
    );
    workspace.updateFileContent('pubspec.yaml', source);
  }

  void _readSection(
    Object? raw,
    PackageDependencyGroup group,
    Map<String, String> lockVersions,
    List<PackageDependencyInfo> output,
  ) {
    if (raw is! YamlMap) return;

    for (final entry in raw.entries) {
      final name = '${entry.key}';
      output.add(
        PackageDependencyInfo(
          name: name,
          constraint: _constraintLabel(entry.value),
          group: group,
          source: _sourceOf(entry.value),
          resolvedVersion: lockVersions[name],
        ),
      );
    }
  }

  Map<String, String> _readLockVersions(WorkspaceController workspace) {
    final lock = workspace.entryAt('pubspec.lock');
    if (lock == null || !lock.isFile || !lock.isText) {
      return const <String, String>{};
    }

    try {
      final root = loadYaml(lock.content);
      if (root is! YamlMap || root['packages'] is! YamlMap) {
        return const <String, String>{};
      }

      final result = <String, String>{};
      final packages = root['packages'] as YamlMap;
      for (final entry in packages.entries) {
        final value = entry.value;
        if (value is YamlMap && value['version'] != null) {
          result['${entry.key}'] = '${value['version']}';
        }
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  String _constraintLabel(Object? raw) {
    if (raw is String) return raw;
    if (raw is YamlMap) {
      if (raw['sdk'] != null) return 'sdk: ${raw['sdk']}';
      if (raw['git'] != null) return 'git';
      if (raw['path'] != null) return 'path: ${raw['path']}';
      if (raw['version'] != null) return '${raw['version']}';
      if (raw['hosted'] != null) return 'hosted';
    }
    return '$raw';
  }

  PackageDependencySource _sourceOf(Object? raw) {
    if (raw is String) return PackageDependencySource.hosted;
    if (raw is YamlMap) {
      if (raw['sdk'] != null) return PackageDependencySource.sdk;
      if (raw['git'] != null) return PackageDependencySource.git;
      if (raw['path'] != null) return PackageDependencySource.path;
      if (raw['hosted'] != null || raw['version'] != null) {
        return PackageDependencySource.hosted;
      }
    }
    return PackageDependencySource.other;
  }

  String _pubspecContent(WorkspaceController workspace) {
    final entry = workspace.entryAt('pubspec.yaml');
    if (entry == null || !entry.isFile || !entry.isText) {
      throw const FormatException('Workspace does not contain pubspec.yaml.');
    }
    return entry.content;
  }

  String _removeEntry(String source, String section, String packageName) {
    final hadTrailingNewline = source.endsWith('\n');
    final lines = source.split('\n');
    final sectionIndex = lines.indexWhere(
      (line) => line.trimRight() == '$section:',
    );
    if (sectionIndex == -1) return source;

    final sectionEnd = _sectionEnd(lines, sectionIndex);
    final matcher = RegExp('^  ${RegExp.escape(packageName)}:\\s*');
    var start = -1;
    for (var i = sectionIndex + 1; i < sectionEnd; i++) {
      if (matcher.hasMatch(lines[i])) {
        start = i;
        break;
      }
    }
    if (start == -1) return source;

    var end = start + 1;
    while (end < sectionEnd) {
      final line = lines[end];
      if (RegExp(r'^  [A-Za-z0-9_]+:\s*').hasMatch(line)) break;
      if (line.isNotEmpty && !line.startsWith(' ')) break;
      end += 1;
    }
    lines.removeRange(start, end);
    return _joinLines(lines, hadTrailingNewline);
  }

  String _insertEntry(
    String source,
    String section,
    String packageName,
    String constraint,
  ) {
    final hadTrailingNewline = source.endsWith('\n');
    final lines = source.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

    final sectionIndex = lines.indexWhere(
      (line) => line.trimRight() == '$section:',
    );
    if (sectionIndex == -1) {
      final flutterIndex = lines.indexWhere(
        (line) => line.trimRight() == 'flutter:',
      );
      final insertAt = flutterIndex == -1 ? lines.length : flutterIndex;
      lines.insertAll(insertAt, <String>[
        '$section:',
        '  $packageName: $constraint',
        '',
      ]);
      return _joinLines(lines, true);
    }

    var insertAt = _sectionEnd(lines, sectionIndex);
    while (insertAt > sectionIndex + 1 &&
        lines[insertAt - 1].trim().isEmpty) {
      insertAt -= 1;
    }
    lines.insert(insertAt, '  $packageName: $constraint');
    return _joinLines(lines, hadTrailingNewline);
  }

  int _sectionEnd(List<String> lines, int sectionIndex) {
    for (var i = sectionIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
        return i;
      }
    }
    return lines.length;
  }

  String _joinLines(List<String> lines, bool trailingNewline) {
    final joined = lines.join('\n');
    return trailingNewline ? '$joined\n' : joined;
  }

  void _validatePackageName(String value) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
      throw FormatException('Invalid Dart package name: $value');
    }
  }
}
