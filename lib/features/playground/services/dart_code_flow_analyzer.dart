import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../workspace/models/workspace_entry.dart';

class CodeFlowLocation {
  const CodeFlowLocation({
    required this.filePath,
    required this.line,
    required this.column,
    required this.length,
  });

  final String filePath;
  final int line;
  final int column;
  final int length;
}

class CodeFlowCall {
  const CodeFlowCall({
    required this.name,
    required this.location,
  });

  final String name;
  final CodeFlowLocation location;
}

class CodeFlowEdge {
  const CodeFlowEdge({
    required this.sourceName,
    required this.source,
    required this.callSite,
    required this.targetName,
    required this.target,
  });

  final String sourceName;
  final CodeFlowLocation source;
  final CodeFlowLocation callSite;
  final String targetName;
  final CodeFlowLocation target;
}

class CodeFlowNode {
  const CodeFlowNode({
    required this.name,
    required this.displayName,
    required this.location,
    this.children = const <CodeFlowNode>[],
    this.isCycle = false,
  });

  final String name;
  final String displayName;
  final CodeFlowLocation location;
  final List<CodeFlowNode> children;
  final bool isCycle;
}

class CodeFlowGraph {
  const CodeFlowGraph({
    required this.root,
    required this.callersRoot,
    required this.scannedFiles,
    required this.declarationCount,
    required this.edges,
  });

  /// Methods/functions called by the declaration under the cursor.
  final CodeFlowNode root;

  /// Methods/functions that call the declaration under the cursor.
  final CodeFlowNode callersRoot;

  final int scannedFiles;
  final int declarationCount;

  /// Concrete call-site edges across the parsed Workspace.
  ///
  /// Unlike the tree nodes, this preserves repeated calls to the same target so
  /// Monaco can later draw a wire from each invocation to its declaration.
  final List<CodeFlowEdge> edges;

  int get directCalleeCount => root.children.length;
  int get directCallerCount => callersRoot.children.length;
}

class CodeFlowAnalysisException implements Exception {
  const CodeFlowAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lightweight, browser-safe Dart call-flow analysis for the current Workspace.
///
/// This intentionally does not try to replace the Dart analysis server. It
/// parses the Workspace source already available in the browser, indexes Dart
/// function/method declarations, and connects method invocations by name. The
/// result is useful for learning and architecture tracing while remaining fast
/// enough to run without sending source code to the Runner backend.
class DartCodeFlowAnalyzer {
  const DartCodeFlowAnalyzer({this.maxDepth = 5});

  final int maxDepth;

  CodeFlowGraph analyze({
    required List<WorkspaceEntry> entries,
    required String activeFilePath,
    required int cursorLine,
    required int cursorColumn,
  }) {
    final dartFiles = entries
        .where(
          (entry) =>
              entry.isFile && entry.isText && entry.path.endsWith('.dart'),
        )
        .toList(growable: false);

    if (dartFiles.isEmpty) {
      throw const CodeFlowAnalysisException('当前 Workspace 没有可分析的 Dart 文件。');
    }

    final declarations = <_FlowDeclaration>[];
    final sourceByPath = <String, String>{};

    for (final file in dartFiles) {
      sourceByPath[file.path] = file.content;
      final parsed = parseString(
        content: file.content,
        throwIfDiagnostics: false,
      );
      final collector = _DeclarationCollector(
        filePath: file.path,
        source: file.content,
      );
      parsed.unit.accept(collector);
      declarations.addAll(collector.declarations);
    }

    if (declarations.isEmpty) {
      throw const CodeFlowAnalysisException('没有找到可追踪的 Dart 方法或函数。');
    }

    for (final declaration in declarations) {
      final calls = _MethodCallCollector(
        filePath: declaration.filePath,
        source: sourceByPath[declaration.filePath]!,
      );
      declaration.body.accept(calls);
      declaration.calls.addAll(calls.calls);
    }

    final byName = <String, List<_FlowDeclaration>>{};
    for (final declaration in declarations) {
      byName.putIfAbsent(declaration.name, () => <_FlowDeclaration>[]).add(
            declaration,
          );
    }

    final callersByTargetKey = _buildCallersIndex(
      declarations: declarations,
      byName: byName,
    );

    final activeSource = sourceByPath[activeFilePath];
    if (activeSource == null) {
      throw const CodeFlowAnalysisException('请先打开一个 Dart 文件，再分析调用链。');
    }

    final cursorOffset = _offsetForLineColumn(
      activeSource,
      cursorLine,
      cursorColumn,
    );
    final rootDeclaration = _findRootDeclaration(
      declarations: declarations,
      byName: byName,
      activeFilePath: activeFilePath,
      activeSource: activeSource,
      cursorOffset: cursorOffset,
    );

    if (rootDeclaration == null) {
      throw const CodeFlowAnalysisException(
        '把光标放进一个 Dart 方法/函数内部，或放在它的名称上，然后再点击分析。',
      );
    }

    return CodeFlowGraph(
      root: _buildOutgoingNode(
        rootDeclaration,
        byName: byName,
        depth: 0,
        stack: const <String>{},
      ),
      callersRoot: _buildIncomingNode(
        rootDeclaration,
        callersByTargetKey: callersByTargetKey,
        depth: 0,
        stack: const <String>{},
      ),
      scannedFiles: dartFiles.length,
      declarationCount: declarations.length,
      edges: _buildEdges(
        declarations: declarations,
        byName: byName,
      ),
    );
  }

  List<CodeFlowEdge> _buildEdges({
    required List<_FlowDeclaration> declarations,
    required Map<String, List<_FlowDeclaration>> byName,
  }) {
    final edges = <CodeFlowEdge>[];
    final seen = <String>{};

    for (final caller in declarations) {
      for (final call in caller.calls) {
        final targets = _resolveTargets(
          caller,
          call.name,
          byName[call.name] ?? const <_FlowDeclaration>[],
        );

        for (final target in targets) {
          final key = '${caller.key}#'
              '${call.location.line}:${call.location.column}->${target.key}';
          if (!seen.add(key)) continue;

          edges.add(
            CodeFlowEdge(
              sourceName: caller.displayName,
              source: caller.location,
              callSite: call.location,
              targetName: target.displayName,
              target: target.location,
            ),
          );
        }
      }
    }

    return List<CodeFlowEdge>.unmodifiable(edges);
  }

  Map<String, List<_FlowDeclaration>> _buildCallersIndex({
    required List<_FlowDeclaration> declarations,
    required Map<String, List<_FlowDeclaration>> byName,
  }) {
    final callersByTargetKey = <String, List<_FlowDeclaration>>{};

    for (final caller in declarations) {
      final linkedTargets = <String>{};
      for (final call in caller.calls) {
        final targets = _resolveTargets(
          caller,
          call.name,
          byName[call.name] ?? const <_FlowDeclaration>[],
        );
        for (final target in targets) {
          if (!linkedTargets.add(target.key)) continue;
          callersByTargetKey
              .putIfAbsent(target.key, () => <_FlowDeclaration>[])
              .add(caller);
        }
      }
    }

    return callersByTargetKey;
  }

  _FlowDeclaration? _findRootDeclaration({
    required List<_FlowDeclaration> declarations,
    required Map<String, List<_FlowDeclaration>> byName,
    required String activeFilePath,
    required String activeSource,
    required int cursorOffset,
  }) {
    final containing = declarations
        .where(
          (declaration) =>
              declaration.filePath == activeFilePath &&
              cursorOffset >= declaration.startOffset &&
              cursorOffset <= declaration.endOffset,
        )
        .toList()
      ..sort(
        (a, b) => (a.endOffset - a.startOffset).compareTo(
          b.endOffset - b.startOffset,
        ),
      );

    if (containing.isNotEmpty) return containing.first;

    final identifier = _identifierAt(activeSource, cursorOffset);
    if (identifier == null) return null;

    final candidates = byName[identifier];
    if (candidates == null || candidates.isEmpty) return null;

    for (final candidate in candidates) {
      if (candidate.filePath == activeFilePath) return candidate;
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  CodeFlowNode _buildOutgoingNode(
    _FlowDeclaration declaration, {
    required Map<String, List<_FlowDeclaration>> byName,
    required int depth,
    required Set<String> stack,
  }) {
    final key = declaration.key;
    final cycle = stack.contains(key);
    if (cycle || depth >= maxDepth) {
      return declaration.toNode(isCycle: cycle);
    }

    final nextStack = <String>{...stack, key};
    final children = <CodeFlowNode>[];
    final addedTargets = <String>{};

    for (final call in declaration.calls) {
      final targets = _resolveTargets(
        declaration,
        call.name,
        byName[call.name] ?? const <_FlowDeclaration>[],
      );
      for (final target in targets) {
        if (!addedTargets.add(target.key)) continue;
        children.add(
          _buildOutgoingNode(
            target,
            byName: byName,
            depth: depth + 1,
            stack: nextStack,
          ),
        );
      }
    }

    return declaration.toNode(children: children);
  }

  CodeFlowNode _buildIncomingNode(
    _FlowDeclaration declaration, {
    required Map<String, List<_FlowDeclaration>> callersByTargetKey,
    required int depth,
    required Set<String> stack,
  }) {
    final key = declaration.key;
    final cycle = stack.contains(key);
    if (cycle || depth >= maxDepth) {
      return declaration.toNode(isCycle: cycle);
    }

    final nextStack = <String>{...stack, key};
    final children = <CodeFlowNode>[];
    final addedCallers = <String>{};

    for (final caller
        in callersByTargetKey[key] ?? const <_FlowDeclaration>[]) {
      if (!addedCallers.add(caller.key)) continue;
      children.add(
        _buildIncomingNode(
          caller,
          callersByTargetKey: callersByTargetKey,
          depth: depth + 1,
          stack: nextStack,
        ),
      );
    }

    return declaration.toNode(children: children);
  }

  List<_FlowDeclaration> _resolveTargets(
    _FlowDeclaration caller,
    String callName,
    List<_FlowDeclaration> candidates,
  ) {
    if (candidates.isEmpty) return const <_FlowDeclaration>[];

    final sameOwner = candidates
        .where(
          (candidate) =>
              candidate.filePath == caller.filePath &&
              candidate.owner == caller.owner,
        )
        .toList(growable: false);
    if (sameOwner.isNotEmpty) return <_FlowDeclaration>[sameOwner.first];

    final sameFile = candidates
        .where((candidate) => candidate.filePath == caller.filePath)
        .toList(growable: false);
    if (sameFile.isNotEmpty) return <_FlowDeclaration>[sameFile.first];

    if (candidates.length == 1) return <_FlowDeclaration>[candidates.single];

    // Without resolved types we cannot know which implementation a receiver
    // uses. Showing at most two candidates is more honest than silently
    // pretending one arbitrary method is definitely the target.
    return candidates.take(2).toList(growable: false);
  }
}

class _FlowDeclaration {
  _FlowDeclaration({
    required this.name,
    required this.owner,
    required this.filePath,
    required this.location,
    required this.startOffset,
    required this.endOffset,
    required this.body,
  });

  final String name;
  final String? owner;
  final String filePath;
  final CodeFlowLocation location;
  final int startOffset;
  final int endOffset;
  final FunctionBody body;
  final List<CodeFlowCall> calls = <CodeFlowCall>[];

  String get key => '$filePath#$startOffset';
  String get displayName => owner == null ? name : '$owner.$name';

  CodeFlowNode toNode({
    List<CodeFlowNode> children = const <CodeFlowNode>[],
    bool isCycle = false,
  }) {
    return CodeFlowNode(
      name: name,
      displayName: displayName,
      location: location,
      children: children,
      isCycle: isCycle,
    );
  }
}

class _DeclarationCollector extends RecursiveAstVisitor<void> {
  _DeclarationCollector({
    required this.filePath,
    required this.source,
  });

  final String filePath;
  final String source;
  final List<_FlowDeclaration> declarations = <_FlowDeclaration>[];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    declarations.add(
      _FlowDeclaration(
        name: node.name.lexeme,
        owner: _ownerOf(node),
        filePath: filePath,
        location: _locationFor(
          filePath,
          source,
          node.name.offset,
          node.name.lexeme.length,
        ),
        startOffset: node.offset,
        endOffset: node.end,
        body: node.body,
      ),
    );
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    declarations.add(
      _FlowDeclaration(
        name: node.name.lexeme,
        owner: _ownerOf(node),
        filePath: filePath,
        location: _locationFor(
          filePath,
          source,
          node.name.offset,
          node.name.lexeme.length,
        ),
        startOffset: node.offset,
        endOffset: node.end,
        body: node.functionExpression.body,
      ),
    );
    super.visitFunctionDeclaration(node);
  }

  String? _ownerOf(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ClassDeclaration) return current.name.lexeme;
      current = current.parent;
    }
    return null;
  }
}

class _MethodCallCollector extends RecursiveAstVisitor<void> {
  _MethodCallCollector({
    required this.filePath,
    required this.source,
  });

  final String filePath;
  final String source;
  final List<CodeFlowCall> calls = <CodeFlowCall>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final methodName = node.methodName;
    calls.add(
      CodeFlowCall(
        name: methodName.name,
        location: _locationFor(
          filePath,
          source,
          methodName.offset,
          methodName.length,
        ),
      ),
    );
    super.visitMethodInvocation(node);
  }
}

CodeFlowLocation _locationFor(
  String filePath,
  String source,
  int offset,
  int length,
) {
  var line = 1;
  var column = 1;
  final safeOffset = offset.clamp(0, source.length).toInt();
  for (var i = 0; i < safeOffset; i++) {
    if (source.codeUnitAt(i) == 10) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return CodeFlowLocation(
    filePath: filePath,
    line: line,
    column: column,
    length: length,
  );
}

int _offsetForLineColumn(String source, int line, int column) {
  if (source.isEmpty) return 0;
  final lines = source.split('\n');
  final safeLine = line.clamp(0, lines.length - 1).toInt();
  final safeColumn = column.clamp(0, lines[safeLine].length).toInt();

  var offset = 0;
  for (var i = 0; i < safeLine; i++) {
    offset += lines[i].length + 1;
  }
  return offset + safeColumn;
}

String? _identifierAt(String source, int offset) {
  if (source.isEmpty) return null;
  final safeOffset = offset.clamp(0, source.length).toInt();

  bool isIdentifierCodeUnit(int value) =>
      (value >= 48 && value <= 57) ||
      (value >= 65 && value <= 90) ||
      (value >= 97 && value <= 122) ||
      value == 95 ||
      value == 36;

  var start = safeOffset;
  while (start > 0 && isIdentifierCodeUnit(source.codeUnitAt(start - 1))) {
    start--;
  }

  var end = safeOffset;
  while (end < source.length && isIdentifierCodeUnit(source.codeUnitAt(end))) {
    end++;
  }

  if (start == end) return null;
  return source.substring(start, end);
}
