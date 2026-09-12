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
    this.receiver,
    this.httpMethod,
    this.httpPath,
  });

  final String name;
  final CodeFlowLocation location;

  /// Source expression to the left of the invoked method when available.
  /// This is only used as an extra hint for cross-boundary RPC resolution;
  /// ordinary local-call resolution keeps the original name-based behavior.
  final String? receiver;

  /// Normalized HTTP verb/path when this invocation looks like a concrete
  /// REST request. These hints stay optional so ordinary Dart calls keep
  /// exactly the same resolution behavior.
  final String? httpMethod;
  final String? httpPath;
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
    this.sourceCode = '',
    this.sourceStartLine = 1,
    this.children = const <CodeFlowNode>[],
    this.isCycle = false,
    this.isBackend = false,
  });

  final String name;
  final String displayName;
  final CodeFlowLocation location;

  /// Exact declaration text sliced from the Workspace source that produced
  /// this AST node. This is not generated, summarized, or rewritten.
  final String sourceCode;

  /// 1-based Workspace line where [sourceCode] starts. This is kept separate
  /// from [location] because the function name can appear after metadata or
  /// modifiers on a later line.
  final int sourceStartLine;

  final List<CodeFlowNode> children;
  final bool isCycle;

  /// True for a node that represents backend code. Route adapters set this
  /// directly so the graph does not have to guess the backend from folder
  /// naming conventions.
  final bool isBackend;
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
    final httpBackendRoutes = _collectHttpBackendRoutes(entries);

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
        httpBackendRoutes: httpBackendRoutes,
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
        httpBackendRoutes: httpBackendRoutes,
      ),
    );
  }

  List<CodeFlowEdge> _buildEdges({
    required List<_FlowDeclaration> declarations,
    required Map<String, List<_FlowDeclaration>> byName,
    required List<_HttpBackendRoute> httpBackendRoutes,
  }) {
    final edges = <CodeFlowEdge>[];

    for (final caller in declarations) {
      for (final call in caller.calls) {
        final targets = _resolveCallTargets(
          caller,
          call,
          byName[call.name] ?? const <_FlowDeclaration>[],
        );

        for (final target in targets) {
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

        final httpTarget = _resolveHttpBackendRoute(
          call,
          httpBackendRoutes,
        );
        if (httpTarget != null) {
          edges.add(
            CodeFlowEdge(
              sourceName: caller.displayName,
              source: caller.location,
              callSite: call.location,
              targetName: httpTarget.displayName,
              target: httpTarget.location,
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
        final targets = _resolveCallTargets(
          caller,
          call,
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
    required List<_HttpBackendRoute> httpBackendRoutes,
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
      final targets = _resolveCallTargets(
        declaration,
        call,
        byName[call.name] ?? const <_FlowDeclaration>[],
      );
      for (final target in targets) {
        if (!addedTargets.add(target.key)) continue;
        children.add(
          _buildOutgoingNode(
            target,
            byName: byName,
            httpBackendRoutes: httpBackendRoutes,
            depth: depth + 1,
            stack: nextStack,
          ),
        );
      }

      final httpTarget = _resolveHttpBackendRoute(
        call,
        httpBackendRoutes,
      );
      if (httpTarget != null && addedTargets.add(httpTarget.key)) {
        children.add(httpTarget.toNode());
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
    if (sameFile.length == 1) {
      return <_FlowDeclaration>[sameFile.single];
    }

    if (candidates.length == 1) return <_FlowDeclaration>[candidates.single];

    // A name-only match is not enough to claim a real call target when more
    // than one Workspace declaration is possible. Leave ambiguous calls out
    // of the definite graph until a type-resolved analyzer can identify them.
    return const <_FlowDeclaration>[];
  }

  List<_FlowDeclaration> _resolveCallTargets(
    _FlowDeclaration caller,
    CodeFlowCall call,
    List<_FlowDeclaration> candidates,
  ) {
    // Preserve the exact pre-existing local-call behavior first. The RPC hint
    // is only consulted when the old resolver would have considered the call
    // ambiguous.
    final localTargets = _resolveTargets(caller, call.name, candidates);
    if (localTargets.isNotEmpty) return localTargets;

    final serverpodEndpoint = _serverpodEndpointName(call.receiver);
    if (serverpodEndpoint == null) return const <_FlowDeclaration>[];

    final endpointTargets = candidates
        .where(
          (candidate) =>
              _isServerpodBackendEndpoint(candidate, serverpodEndpoint),
        )
        .toList(growable: false);
    return endpointTargets.length == 1
        ? <_FlowDeclaration>[endpointTargets.single]
        : const <_FlowDeclaration>[];
  }

  _HttpBackendRoute? _resolveHttpBackendRoute(
    CodeFlowCall call,
    List<_HttpBackendRoute> routes,
  ) {
    final method = call.httpMethod;
    final clientPath = call.httpPath;
    if (method == null || clientPath == null) return null;

    final scored = <(_HttpBackendRoute, int)>[];
    for (final route in routes) {
      if (route.method != method) continue;
      final score = _httpRouteMatchScore(clientPath, route.path);
      if (score != null) scored.add((route, score));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    if (scored.isEmpty) return null;
    if (scored.length == 1) return scored.single.$1;
    return scored[0].$2 > scored[1].$2 ? scored.first.$1 : null;
  }

  int? _httpRouteMatchScore(String clientPath, String routePath) {
    final client = _httpPathSegments(clientPath);
    final route = _httpPathSegments(routePath);
    if (client.isEmpty || route.isEmpty) return null;

    final shorter = client.length <= route.length ? client : route;
    final longer = client.length <= route.length ? route : client;
    final clientIsShorter = client.length <= route.length;
    final start = longer.length - shorter.length;
    var score = 0;

    for (var index = 0; index < shorter.length; index++) {
      final clientSegment =
          clientIsShorter ? shorter[index] : longer[start + index];
      final routeSegment =
          clientIsShorter ? longer[start + index] : shorter[index];
      final clientDynamic = _isDynamicHttpSegment(clientSegment);
      final routeDynamic = _isDynamicHttpSegment(routeSegment);

      if (!clientDynamic && !routeDynamic) {
        if (clientSegment != routeSegment) return null;
        score += 4;
      } else if (clientDynamic && routeDynamic) {
        score += 3;
      } else if (!clientDynamic && routeDynamic) {
        score += 1;
      }
    }

    return score;
  }

  List<String> _httpPathSegments(String value) {
    var path = value.trim();
    if (path.isEmpty) return const <String>[];

    final schemeIndex = path.indexOf('://');
    if (schemeIndex >= 0) {
      final slash = path.indexOf('/', schemeIndex + 3);
      path = slash >= 0 ? path.substring(slash) : '/';
    }

    final query = path.indexOf('?');
    if (query >= 0) path = path.substring(0, query);
    final fragment = path.indexOf('#');
    if (fragment >= 0) path = path.substring(0, fragment);

    return path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  bool _isDynamicHttpSegment(String segment) =>
      segment == '*' ||
      segment.startsWith(':') ||
      (segment.startsWith('{') && segment.endsWith('}')) ||
      (segment.startsWith('[') && segment.endsWith(']')) ||
      segment.startsWith('<');

  String? _serverpodEndpointName(String? receiver) {
    if (receiver == null || receiver.isEmpty) return null;
    final compact = receiver.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(
      r'(?:^|\.)client\.([A-Za-z_$][A-Za-z0-9_$]*)$',
    ).firstMatch(compact);
    return match?.group(1);
  }

  bool _isServerpodBackendEndpoint(
    _FlowDeclaration candidate,
    String endpointName,
  ) {
    final owner = candidate.owner;
    if (owner == null || !owner.endsWith('Endpoint')) return false;
    if (!_isBackendSourcePath(candidate.filePath)) return false;

    final base = owner.substring(0, owner.length - 'Endpoint'.length);
    if (base.isEmpty) return false;
    final exposedName = '${base[0].toLowerCase()}${base.substring(1)}';
    return exposedName == endpointName;
  }

  bool _isBackendSourcePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized == 'backend' ||
        normalized.startsWith('backend/') ||
        normalized.startsWith('server/') ||
        normalized.contains('/server/') ||
        normalized.contains('_server/lib/');
  }
}

class _HttpBackendRoute {
  const _HttpBackendRoute({
    required this.method,
    required this.path,
    required this.filePath,
    required this.location,
    required this.sourceCode,
    required this.sourceStartLine,
  });

  final String method;
  final String path;
  final String filePath;
  final CodeFlowLocation location;
  final String sourceCode;
  final int sourceStartLine;

  String get key => '$filePath#${location.line}#$method#$path';
  String get displayName => '$method $path';
  CodeFlowNode toNode() => CodeFlowNode(
        name: '$method $path',
        displayName: displayName,
        location: location,
        sourceCode: sourceCode,
        sourceStartLine: sourceStartLine,
        isBackend: true,
      );
}

List<_HttpBackendRoute> _collectHttpBackendRoutes(
  List<WorkspaceEntry> entries,
) {
  final backendRoots = _detectHttpBackendRoots(entries);
  final sourceFiles = entries
      .where(
        (entry) =>
            entry.isFile &&
            entry.isText &&
            _isSupportedBackendSourceFile(entry.path) &&
            (_isUnderAnyBackendRoot(entry.path, backendRoots) ||
                _looksLikeConventionalBackendPath(entry.path)),
      )
      .toList(growable: false);

  if (sourceFiles.isEmpty) return const <_HttpBackendRoute>[];

  final mountPrefixes = <String, List<String>>{};
  for (final file in sourceFiles) {
    _collectJavascriptMountPrefixes(file.content, mountPrefixes);
  }

  final routes = <_HttpBackendRoute>[];
  for (final file in sourceFiles) {
    routes.addAll(
      _collectJavascriptRoutes(
        file.path,
        file.content,
        mountPrefixes,
      ),
    );
    routes
        .addAll(_collectDecoratorAndAnnotationRoutes(file.path, file.content));
    routes.addAll(_collectInlineFrameworkRoutes(file.path, file.content));
  }

  final unique = <String, _HttpBackendRoute>{};
  for (final route in routes) {
    unique.putIfAbsent(route.key, () => route);
  }
  return List<_HttpBackendRoute>.unmodifiable(unique.values);
}

Set<String> _detectHttpBackendRoots(List<WorkspaceEntry> entries) {
  final roots = <String>{};

  for (final entry in entries) {
    if (!entry.isFile || !entry.isText) continue;
    final path = entry.path.replaceAll('\\', '/');
    final lowerPath = path.toLowerCase();
    final content = entry.content.toLowerCase();

    bool isBackendManifest = false;
    if (lowerPath.endsWith('/package.json') || lowerPath == 'package.json') {
      isBackendManifest = const <String>[
        '"express"',
        '"@nestjs/',
        '"fastify"',
        '"koa"',
        '"hono"',
        '"elysia"',
        '"@adonisjs/',
      ].any(content.contains);
    } else if (lowerPath.endsWith('/requirements.txt') ||
        lowerPath.endsWith('/pyproject.toml') ||
        lowerPath == 'requirements.txt' ||
        lowerPath == 'pyproject.toml') {
      isBackendManifest = const <String>[
        'fastapi',
        'flask',
        'django',
        'starlette',
        'sanic',
      ].any(content.contains);
    } else if (lowerPath.endsWith('/pom.xml') ||
        lowerPath.endsWith('/build.gradle') ||
        lowerPath.endsWith('/build.gradle.kts') ||
        lowerPath == 'pom.xml') {
      isBackendManifest = content.contains('spring');
    } else if (lowerPath.endsWith('.csproj')) {
      isBackendManifest = content.contains('microsoft.aspnetcore') ||
          content.contains('microsoft.net.sdk.web');
    } else if (lowerPath.endsWith('/go.mod') || lowerPath == 'go.mod') {
      isBackendManifest = const <String>[
        'gin-gonic/gin',
        'gofiber/fiber',
        'labstack/echo',
        'go-chi/chi',
      ].any(content.contains);
    } else if (lowerPath.endsWith('/cargo.toml') || lowerPath == 'cargo.toml') {
      isBackendManifest = const <String>[
        'axum',
        'actix-web',
        'rocket',
        'warp',
      ].any(content.contains);
    } else if (lowerPath.endsWith('/composer.json') ||
        lowerPath == 'composer.json') {
      isBackendManifest = const <String>[
        'laravel/framework',
        'laravel/lumen',
        'slim/slim',
      ].any(content.contains);
    } else if (lowerPath.endsWith('/gemfile') || lowerPath == 'gemfile') {
      isBackendManifest = content.contains("gem 'rails'") ||
          content.contains('gem "rails"') ||
          content.contains("gem 'sinatra'") ||
          content.contains('gem "sinatra"');
    }

    if (isBackendManifest) roots.add(_parentPath(path));
  }

  return roots;
}

bool _isUnderAnyBackendRoot(String path, Set<String> roots) {
  final normalized = path.replaceAll('\\', '/');
  for (final root in roots) {
    if (root.isEmpty || normalized == root || normalized.startsWith('$root/')) {
      return true;
    }
  }
  return false;
}

String _parentPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? '' : normalized.substring(0, slash);
}

bool _looksLikeConventionalBackendPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized.startsWith('backend/') ||
      normalized.startsWith('server/') ||
      normalized.startsWith('api/') ||
      normalized.contains('/backend/') ||
      normalized.contains('/server/') ||
      normalized.contains('/api/');
}

bool _isSupportedBackendSourceFile(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  if (normalized.contains('/generated/') ||
      normalized.contains('/node_modules/') ||
      normalized.contains('/dist/') ||
      normalized.contains('/build/')) {
    return false;
  }

  const extensions = <String>{
    '.ts',
    '.tsx',
    '.js',
    '.jsx',
    '.mjs',
    '.cjs',
    '.py',
    '.java',
    '.kt',
    '.kts',
    '.cs',
    '.go',
    '.rs',
    '.php',
    '.rb',
  };
  return extensions.any(normalized.endsWith);
}

void _collectJavascriptMountPrefixes(
  String source,
  Map<String, List<String>> prefixes,
) {
  final pattern = RegExp(
    r'''\b[A-Za-z_$][A-Za-z0-9_$]*\.use\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*([A-Za-z_$][A-Za-z0-9_$]*)''',
    multiLine: true,
  );

  for (final match in pattern.allMatches(source)) {
    final prefix = match.group(1);
    final router = match.group(2);
    if (prefix == null || router == null || !prefix.startsWith('/')) continue;
    prefixes.putIfAbsent(router, () => <String>[]).add(prefix);
  }
}

List<_HttpBackendRoute> _collectJavascriptRoutes(
  String filePath,
  String source,
  Map<String, List<String>> mountPrefixes,
) {
  final routes = <_HttpBackendRoute>[];
  final pattern = RegExp(
    r'''\b([A-Za-z_$][A-Za-z0-9_$]*)\.(get|post|put|patch|delete|head|options)\s*\(\s*['"`]([^'"`]+)['"`]''',
    caseSensitive: false,
    multiLine: true,
  );

  for (final match in pattern.allMatches(source)) {
    final receiver = match.group(1);
    final method = match.group(2)?.toUpperCase();
    final localPath = match.group(3);
    if (receiver == null ||
        method == null ||
        localPath == null ||
        !localPath.startsWith('/')) {
      continue;
    }

    final prefixes = mountPrefixes[receiver];
    final receiverHint = receiver.toLowerCase();
    final looksLikeRouter = receiverHint == 'app' ||
        receiverHint == 'router' ||
        receiverHint == 'server' ||
        receiverHint.contains('router') ||
        receiverHint.contains('fastify') ||
        receiverHint.contains('hono');
    if ((prefixes == null || prefixes.isEmpty) && !looksLikeRouter) {
      continue;
    }

    if (prefixes == null || prefixes.isEmpty) {
      routes.add(
        _httpRouteFromMatch(
          filePath: filePath,
          source: source,
          match: match,
          method: method,
          path: localPath,
        ),
      );
      continue;
    }

    for (final prefix in prefixes) {
      routes.add(
        _httpRouteFromMatch(
          filePath: filePath,
          source: source,
          match: match,
          method: method,
          path: _joinHttpPaths(prefix, localPath),
        ),
      );
    }
  }

  return routes;
}

List<_HttpBackendRoute> _collectDecoratorAndAnnotationRoutes(
  String filePath,
  String source,
) {
  final routes = <_HttpBackendRoute>[];

  // NestJS: @Controller('/users') + @Get('/me')
  final nestBlocks = RegExp(
    r'''@Controller\s*\(\s*['"`]([^'"`]*)['"`]\s*\)([\s\S]*?)(?=@Controller\s*\(|$)''',
  );
  for (final block in nestBlocks.allMatches(source)) {
    final prefix = block.group(1) ?? '';
    final body = block.group(2) ?? '';
    final bodyOffset = block.start + (block.group(0)?.indexOf(body) ?? 0);
    final routePattern = RegExp(
      r'''@(Get|Post|Put|Patch|Delete|Head|Options)\s*\(\s*(?:['"`]([^'"`]*)['"`])?\s*\)''',
      caseSensitive: false,
    );
    for (final route in routePattern.allMatches(body)) {
      final method = route.group(1)?.toUpperCase();
      if (method == null) continue;
      routes.add(
        _httpRouteFromOffset(
          filePath: filePath,
          source: source,
          offset: bodyOffset + route.start,
          length: route.group(0)?.length ?? 1,
          method: method,
          path: _joinHttpPaths(prefix, route.group(2) ?? ''),
        ),
      );
    }
  }

  // Spring Boot / Kotlin Spring:
  // @RequestMapping('/users') + @GetMapping('/me')
  final springBlocks = RegExp(
    r'''@RequestMapping\s*\(\s*(?:value\s*=\s*)?['"]([^'"]*)['"][^)]*\)([\s\S]*?)(?=@RequestMapping\s*\(|$)''',
  );
  for (final block in springBlocks.allMatches(source)) {
    final prefix = block.group(1) ?? '';
    final body = block.group(2) ?? '';
    final bodyOffset = block.start + (block.group(0)?.indexOf(body) ?? 0);
    final routePattern = RegExp(
      r'''@(Get|Post|Put|Patch|Delete)Mapping\s*\(\s*(?:value\s*=\s*)?['"]([^'"]*)['"][^)]*\)''',
      caseSensitive: false,
    );
    for (final route in routePattern.allMatches(body)) {
      final method = route.group(1)?.toUpperCase();
      if (method == null) continue;
      routes.add(
        _httpRouteFromOffset(
          filePath: filePath,
          source: source,
          offset: bodyOffset + route.start,
          length: route.group(0)?.length ?? 1,
          method: method,
          path: _joinHttpPaths(prefix, route.group(2) ?? ''),
        ),
      );
    }
  }

  // ASP.NET controllers: [Route('api/users')] + [HttpGet('me')]
  final dotnetBlocks = RegExp(
    r'''\[Route\s*\(\s*["']([^"']*)["']\s*\)\]([\s\S]*?)(?=\[Route\s*\(|$)''',
  );
  for (final block in dotnetBlocks.allMatches(source)) {
    final prefix = block.group(1) ?? '';
    final body = block.group(2) ?? '';
    final bodyOffset = block.start + (block.group(0)?.indexOf(body) ?? 0);
    final routePattern = RegExp(
      r'''\[Http(Get|Post|Put|Patch|Delete|Head|Options)(?:\s*\(\s*["']([^"']*)["']\s*\))?\]''',
      caseSensitive: false,
    );
    for (final route in routePattern.allMatches(body)) {
      final method = route.group(1)?.toUpperCase();
      if (method == null) continue;
      routes.add(
        _httpRouteFromOffset(
          filePath: filePath,
          source: source,
          offset: bodyOffset + route.start,
          length: route.group(0)?.length ?? 1,
          method: method,
          path: _joinHttpPaths(prefix, route.group(2) ?? ''),
        ),
      );
    }
  }

  return routes;
}

List<_HttpBackendRoute> _collectInlineFrameworkRoutes(
  String filePath,
  String source,
) {
  final routes = <_HttpBackendRoute>[];

  final patterns = <RegExp>[
    // FastAPI / Flask and similar decorators.
    RegExp(
      r'''@[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete|head|options)\s*\(\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    ),
    // ASP.NET minimal APIs.
    RegExp(
      r'''\.Map(Get|Post|Put|Patch|Delete)\s*\(\s*["']([^"']+)["']''',
      caseSensitive: false,
    ),
    // Go Gin / Echo / Fiber style routers.
    RegExp(
      r'''\.(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*\(\s*["`]([^"`]+)["`]''',
      caseSensitive: false,
    ),
    // Laravel.
    RegExp(
      r'''Route::(get|post|put|patch|delete|options)\s*\(\s*['"]([^'"]+)['"]''',
      caseSensitive: false,
    ),
    // Rails-style declarations.
    RegExp(
      r'''^\s*(get|post|put|patch|delete)\s+['"]([^'"]+)['"]''',
      caseSensitive: false,
      multiLine: true,
    ),
    // Rust Axum: .route('/users', get(handler))
    RegExp(
      r'''\.route\s*\(\s*["']([^"']+)["']\s*,\s*(get|post|put|patch|delete)\s*\(''',
      caseSensitive: false,
    ),
  ];

  for (var patternIndex = 0; patternIndex < patterns.length; patternIndex++) {
    final pattern = patterns[patternIndex];
    for (final match in pattern.allMatches(source)) {
      String? method;
      String? path;
      if (patternIndex == patterns.length - 1) {
        path = match.group(1);
        method = match.group(2)?.toUpperCase();
      } else {
        method = match.group(1)?.toUpperCase();
        path = match.group(2);
      }

      if (method == null || path == null || !path.startsWith('/')) continue;
      routes.add(
        _httpRouteFromMatch(
          filePath: filePath,
          source: source,
          match: match,
          method: method,
          path: path,
        ),
      );
    }
  }

  return routes;
}

_HttpBackendRoute _httpRouteFromMatch({
  required String filePath,
  required String source,
  required RegExpMatch match,
  required String method,
  required String path,
}) =>
    _httpRouteFromOffset(
      filePath: filePath,
      source: source,
      offset: match.start,
      length: match.group(0)?.length ?? 1,
      method: method,
      path: path,
    );

_HttpBackendRoute _httpRouteFromOffset({
  required String filePath,
  required String source,
  required int offset,
  required int length,
  required String method,
  required String path,
}) {
  final location = _locationFor(filePath, source, offset, length);
  final snippet = _sourceSnippetFromOffset(source, offset);
  return _HttpBackendRoute(
    method: method,
    path: _normalizeHttpPath(path),
    filePath: filePath,
    location: location,
    sourceCode: snippet,
    sourceStartLine: location.line,
  );
}

String _sourceSnippetFromOffset(String source, int offset) {
  final safeOffset = offset.clamp(0, source.length).toInt();
  final lineStart =
      safeOffset == 0 ? 0 : source.lastIndexOf('\n', safeOffset - 1) + 1;
  var lineEnd = lineStart;
  var lines = 0;
  while (lineEnd < source.length && lines < 14) {
    final next = source.indexOf('\n', lineEnd);
    if (next < 0) {
      lineEnd = source.length;
      break;
    }
    lineEnd = next + 1;
    lines++;
  }
  return source.substring(lineStart, lineEnd).trimRight();
}

String _normalizeHttpPath(String value) {
  var path = value.trim();
  if (path.isEmpty) return '/';
  if (!path.startsWith('/')) path = '/$path';
  while (path.contains('//')) {
    path = path.replaceAll('//', '/');
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

String _joinHttpPaths(String first, String second) {
  final left = _normalizeHttpPath(first);
  final right = _normalizeHttpPath(second);
  if (left == '/') return right;
  if (right == '/') return left;
  return _normalizeHttpPath('$left/$right');
}

bool _looksLikeDartBackendPath(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized == 'backend' ||
      normalized.startsWith('backend/') ||
      normalized.startsWith('server/') ||
      normalized.contains('/server/') ||
      normalized.contains('_server/lib/');
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
    required this.sourceCode,
    required this.sourceStartLine,
  });

  final String name;
  final String? owner;
  final String filePath;
  final CodeFlowLocation location;
  final int startOffset;
  final int endOffset;
  final FunctionBody body;
  final String sourceCode;
  final int sourceStartLine;
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
      sourceCode: sourceCode,
      sourceStartLine: sourceStartLine,
      children: children,
      isCycle: isCycle,
      isBackend: _looksLikeDartBackendPath(filePath),
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
        sourceCode: source.substring(node.offset, node.end),
        sourceStartLine: _locationFor(
          filePath,
          source,
          node.offset,
          0,
        ).line,
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
        sourceCode: source.substring(node.offset, node.end),
        sourceStartLine: _locationFor(
          filePath,
          source,
          node.offset,
          0,
        ).line,
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
    final target = node.target;
    final httpMethod = _httpMethodForInvocation(node);
    calls.add(
      CodeFlowCall(
        name: methodName.name,
        location: _locationFor(
          filePath,
          source,
          methodName.offset,
          methodName.length,
        ),
        receiver:
            target == null ? null : source.substring(target.offset, target.end),
        httpMethod: httpMethod,
        httpPath: httpMethod == null ? null : _httpPathForInvocation(node),
      ),
    );
    super.visitMethodInvocation(node);
  }

  String? _httpMethodForInvocation(MethodInvocation node) {
    final method = node.methodName.name.toLowerCase();
    const methods = <String>{
      'get',
      'post',
      'put',
      'patch',
      'delete',
      'head',
      'options',
    };
    return methods.contains(method) ? method.toUpperCase() : null;
  }

  String? _httpPathForInvocation(MethodInvocation node) {
    Expression? expression;
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedExpression) {
        final label = argument.name.label.name.toLowerCase();
        if (label == 'path' || label == 'url' || label == 'uri') {
          expression = argument.expression;
          break;
        }
        continue;
      }
      expression ??= argument;
      break;
    }

    if (expression == null) return null;
    return _httpPathFromExpression(expression);
  }

  String? _httpPathFromExpression(Expression expression) {
    if (expression is SimpleStringLiteral) {
      return expression.value.startsWith('/') ? expression.value : null;
    }

    if (expression is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in expression.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else if (element is InterpolationExpression) {
          buffer.write('*');
        }
      }
      final value = buffer.toString();
      return value.startsWith('/') ? value : null;
    }

    if (expression is MethodInvocation &&
        expression.methodName.name == 'parse' &&
        expression.argumentList.arguments.isNotEmpty) {
      final first = expression.argumentList.arguments.first;
      return _httpPathFromExpression(first);
    }

    return null;
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
