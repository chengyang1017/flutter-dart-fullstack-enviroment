import 'dart:convert';
import 'dart:typed_data';

enum WorkspaceEntryType {
  file,
  directory,
}

enum WorkspaceFileEncoding {
  utf8,
  base64,
}

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.id,
    required this.path,
    required this.type,
    this.content = '',
    this.encoding = WorkspaceFileEncoding.utf8,
  });

  factory WorkspaceEntry.binary({
    required String id,
    required String path,
    required List<int> bytes,
  }) {
    return WorkspaceEntry(
      id: id,
      path: path,
      type: WorkspaceEntryType.file,
      content: base64Encode(bytes),
      encoding: WorkspaceFileEncoding.base64,
    );
  }

  static const runnerBinaryPrefix = '\u0000workspace-base64:';

  final String id;
  final String path;
  final WorkspaceEntryType type;

  /// UTF-8 text when [encoding] is [WorkspaceFileEncoding.utf8], otherwise a
  /// base64 payload. Keeping the payload as a String makes snapshots safe for
  /// Hive/JSON transport without corrupting arbitrary asset bytes.
  final String content;
  final WorkspaceFileEncoding encoding;

  bool get isFile => type == WorkspaceEntryType.file;
  bool get isDirectory => type == WorkspaceEntryType.directory;
  bool get isBinary => isFile && encoding == WorkspaceFileEncoding.base64;
  bool get isText => !isBinary;

  Uint8List get bytes => Uint8List.fromList(
        isBinary ? base64Decode(content) : utf8.encode(content),
      );

  /// Runner HTTP remains backward compatible for text files while binary
  /// files use an unambiguous NUL-prefixed base64 envelope. Imported UTF-8
  /// text is never allowed to contain NUL, so the marker cannot collide with
  /// a portable text file.
  String get runnerContent =>
      isBinary ? '$runnerBinaryPrefix$content' : content;

  static bool isRunnerBinaryContent(String value) =>
      value.startsWith(runnerBinaryPrefix);

  static Uint8List decodeRunnerContent(String value) {
    if (!isRunnerBinaryContent(value)) {
      return Uint8List.fromList(utf8.encode(value));
    }
    return Uint8List.fromList(
      base64Decode(value.substring(runnerBinaryPrefix.length)),
    );
  }

  String get name {
    final index = path.lastIndexOf('/');
    return index == -1 ? path : path.substring(index + 1);
  }

  String get parentPath {
    final index = path.lastIndexOf('/');
    return index == -1 ? '' : path.substring(0, index);
  }

  WorkspaceEntry copyWith({
    String? path,
    String? content,
    WorkspaceFileEncoding? encoding,
  }) {
    return WorkspaceEntry(
      id: id,
      path: path ?? this.path,
      type: type,
      content: content ?? this.content,
      encoding: encoding ?? this.encoding,
    );
  }
}
