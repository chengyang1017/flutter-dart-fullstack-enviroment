import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_entry.dart';
import '../../workspace/models/workspace_snapshot.dart';

class AssetWorkspaceService {
  AssetWorkspaceService(this.workspace);

  static const rootPath = 'assets';

  final WorkspaceController workspace;

  List<WorkspaceEntry> get assetFiles {
    final files = workspace.entries
        .where(
          (entry) =>
              entry.isFile &&
              entry.path.startsWith('$rootPath/'),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return List<WorkspaceEntry>.unmodifiable(files);
  }

  List<WorkspaceEntry> get assetDirectories {
    final directories = workspace.entries
        .where(
          (entry) =>
              entry.isDirectory &&
              (entry.path == rootPath ||
                  entry.path.startsWith('$rootPath/')),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return List<WorkspaceEntry>.unmodifiable(directories);
  }

  bool get hasAssetsDirectory {
    final entry = workspace.entryAt(rootPath);
    return entry != null && entry.isDirectory;
  }

  bool get isAssetsDeclared => isDirectoryDeclared(rootPath);

  bool isDirectoryDeclared(String path) {
    final pubspec = workspace.entryAt('pubspec.yaml');
    if (pubspec == null || !pubspec.isText) return false;

    final escaped = RegExp.escape('$path/');
    return RegExp(
      '^\\s*-\\s+$escaped\\s*(?:#.*)?\$',
      multiLine: true,
    ).hasMatch(pubspec.content);
  }

  void ensureAssetsReady() {
    if (!hasAssetsDirectory) {
      workspace.createDirectory('', rootPath);
    }
    ensureDirectoryDeclaration(rootPath);
  }

  void ensureAssetsDeclaration() => ensureDirectoryDeclaration(rootPath);

  void ensureDirectoryDeclaration(String path) {
    _assertAssetDirectoryOrRoot(path);
    final pubspec = workspace.entryAt('pubspec.yaml');
    if (pubspec == null || !pubspec.isText) {
      throw StateError('当前 Workspace 缺少可编辑的 pubspec.yaml。');
    }
    if (isDirectoryDeclared(path)) return;

    final updated = _insertDirectoryDeclaration(pubspec.content, path);
    workspace.updateFileContent('pubspec.yaml', updated);
  }

  String createFolder(String parentPath, String name) {
    ensureAssetsReady();
    _assertAssetDirectory(parentPath);
    final path = workspace.createDirectory(parentPath, name);
    ensureDirectoryDeclaration(path);
    return path;
  }

  String addBinaryAsset({
    required String parentPath,
    required String name,
    required List<int> bytes,
  }) {
    ensureAssetsReady();
    _assertAssetDirectory(parentPath);
    ensureDirectoryDeclaration(parentPath);

    final path = '$parentPath/$name';
    if (workspace.entryAt(path) != null) {
      throw ArgumentError('资源已存在：$path');
    }

    final snapshot = workspace.createSnapshot();
    final id = 'asset-${DateTime.now().microsecondsSinceEpoch}-$name';
    final asset = WorkspaceEntry.binary(
      id: id,
      path: path,
      bytes: bytes,
    );

    workspace.restoreSnapshot(
      WorkspaceSnapshot(
        entries: <WorkspaceEntry>[
          ...snapshot.entries,
          asset,
        ],
        baseEntries: snapshot.baseEntries,
        openFiles: snapshot.openFiles,
        activePath: snapshot.activePath,
        nextId: snapshot.nextId,
        savedAt: DateTime.now().toUtc(),
        expandedDirectoryIds: snapshot.expandedDirectoryIds,
        editorStates: snapshot.editorStates,
        formatVersion: snapshot.formatVersion,
      ),
    );
    return path;
  }

  void renameAsset(String path, String newName) {
    _assertAssetPath(path);
    workspace.renameEntry(path, newName);
  }

  void deleteAsset(String path) {
    _assertAssetPath(path);
    if (path == rootPath) {
      throw ArgumentError('Assets 根目录由概念模式管理，不能直接删除。');
    }
    workspace.deleteEntry(path);
  }

  void _assertAssetDirectory(String path) {
    if (path != rootPath && !path.startsWith('$rootPath/')) {
      throw ArgumentError('Assets 只能写入 assets/ 范围。');
    }
    final entry = workspace.entryAt(path);
    if (entry == null || !entry.isDirectory) {
      throw ArgumentError('Assets 文件夹不存在：$path');
    }
  }

  void _assertAssetDirectoryOrRoot(String path) {
    if (path != rootPath && !path.startsWith('$rootPath/')) {
      throw ArgumentError('Assets 只能声明 assets/ 范围。');
    }
    final entry = workspace.entryAt(path);
    if (entry == null || !entry.isDirectory) {
      throw ArgumentError('Assets 文件夹不存在：$path');
    }
  }

  void _assertAssetPath(String path) {
    if (!path.startsWith('$rootPath/')) {
      throw ArgumentError('只能管理 assets/ 范围内的资源。');
    }
  }

  String _insertDirectoryDeclaration(String source, String path) {
    final normalized = source.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final declaration = '$path/';

    final flutterIndex = _findTopLevelKey(lines, 'flutter');
    if (flutterIndex == -1) {
      final base = normalized.endsWith('\n') ? normalized : '$normalized\n';
      return '${base}flutter:\n  assets:\n    - $declaration\n';
    }

    final flutterEnd = _sectionEnd(lines, flutterIndex);
    final assetsIndex = _findChildKey(
      lines,
      start: flutterIndex + 1,
      end: flutterEnd,
      key: 'assets',
      minimumIndent: 2,
    );

    if (assetsIndex != -1) {
      final line = lines[assetsIndex];
      final colonIndex = line.indexOf(':');
      final trailing = colonIndex == -1 ? '' : line.substring(colonIndex + 1).trim();
      final indent = _leadingSpaces(line);
      final spaces = List<String>.filled(indent + 2, ' ').join();

      if (trailing.isEmpty || trailing.startsWith('#')) {
        lines.insert(assetsIndex + 1, '$spaces- $declaration');
      } else if (trailing == '[]') {
        lines[assetsIndex] = '${List<String>.filled(indent, ' ').join()}assets:';
        lines.insert(assetsIndex + 1, '$spaces- $declaration');
      } else {
        throw const FormatException(
          '当前 pubspec 的 flutter.assets 使用了概念模式暂不支持的行内写法。',
        );
      }
    } else {
      lines.insertAll(
        flutterEnd,
        <String>[
          '  assets:',
          '    - $declaration',
        ],
      );
    }

    return lines.join('\n');
  }

  int _findTopLevelKey(List<String> lines, String key) {
    final pattern = RegExp('^${RegExp.escape(key)}\\s*:\\s*(?:#.*)?\$');
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) return i;
    }
    return -1;
  }

  int _findChildKey(
    List<String> lines, {
    required int start,
    required int end,
    required String key,
    required int minimumIndent,
  }) {
    final pattern = RegExp('^\\s+${RegExp.escape(key)}\\s*:');
    for (var i = start; i < end; i++) {
      if (_leadingSpaces(lines[i]) >= minimumIndent &&
          pattern.hasMatch(lines[i])) {
        return i;
      }
    }
    return -1;
  }

  int _sectionEnd(List<String> lines, int keyIndex) {
    for (var i = keyIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (_leadingSpaces(line) == 0) return i;
    }
    return lines.length;
  }

  int _leadingSpaces(String value) {
    var count = 0;
    while (count < value.length && value.codeUnitAt(count) == 32) {
      count++;
    }
    return count;
  }
}
