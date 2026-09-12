import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

enum CodeRelationshipKind {
  call,
  recursion,
  callback,
  constructor,
  getterRead,
  setterWrite,
  variableRead,
  variableWrite,
  parameterFlow,
  returnFlow,
  overrideImplementation,
}

extension CodeRelationshipKindLabel on CodeRelationshipKind {
  String get label => switch (this) {
        CodeRelationshipKind.call => '调用',
        CodeRelationshipKind.recursion => '递归',
        CodeRelationshipKind.callback => '回调/函数引用',
        CodeRelationshipKind.constructor => '构造',
        CodeRelationshipKind.getterRead => 'Getter 读取',
        CodeRelationshipKind.setterWrite => 'Setter 写入',
        CodeRelationshipKind.variableRead => '变量读取',
        CodeRelationshipKind.variableWrite => '变量写入',
        CodeRelationshipKind.parameterFlow => '参数传递',
        CodeRelationshipKind.returnFlow => '返回值',
        CodeRelationshipKind.overrideImplementation => 'Override',
      };
}

class CodeRelationshipAnchor {
  const CodeRelationshipAnchor({
    required this.line,
    required this.column,
    required this.length,
    required this.offset,
    required this.label,
  });

  final int line;
  final int column;
  final int length;
  final int offset;
  final String label;
}

class CodeRelationship {
  const CodeRelationship({
    required this.kind,
    required this.source,
    required this.target,
    required this.description,
  });

  final CodeRelationshipKind kind;
  final CodeRelationshipAnchor source;
  final CodeRelationshipAnchor target;
  final String description;
}

class SingleFileCodeRelationshipAnalysis {
  const SingleFileCodeRelationshipAnalysis({
    required this.relationships,
    required this.declarationCount,
  });

  final List<CodeRelationship> relationships;
  final int declarationCount;
}

/// Builds a relationship graph only from declarations physically present in
/// one Dart file. SDK and downloaded-package implementations are deliberately
/// invisible because they never enter the local symbol index.
class SingleFileCodeRelationshipAnalyzer {
  const SingleFileCodeRelationshipAnalyzer();

  SingleFileCodeRelationshipAnalysis analyze({required String source}) {
    if (source.trim().isEmpty) {
      return const SingleFileCodeRelationshipAnalysis(
        relationships: <CodeRelationship>[],
        declarationCount: 0,
      );
    }

    final unit = parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit;
    final symbols = _LocalSymbolCollector(source);
    unit.accept(symbols);

    final relationships = <CodeRelationship>[];
    final seen = <String>{};

    void add(CodeRelationship relationship) {
      final key = '${relationship.kind.name}:'
          '${relationship.source.offset}:${relationship.target.offset}';
      if (seen.add(key)) relationships.add(relationship);
    }

    unit.accept(
      _RelationshipCollector(
        source: source,
        symbols: symbols,
        add: add,
      ),
    );
    _addOverrideRelationships(symbols, add);

    relationships.sort((a, b) {
      final sourceOrder = a.source.offset.compareTo(b.source.offset);
      if (sourceOrder != 0) return sourceOrder;
      final targetOrder = a.target.offset.compareTo(b.target.offset);
      if (targetOrder != 0) return targetOrder;
      return a.kind.index.compareTo(b.kind.index);
    });

    return SingleFileCodeRelationshipAnalysis(
      relationships: List<CodeRelationship>.unmodifiable(relationships),
      declarationCount: symbols.declarationCount,
    );
  }

  void _addOverrideRelationships(
    _LocalSymbolCollector symbols,
    void Function(CodeRelationship relationship) add,
  ) {
    for (final method in symbols.callables) {
      final owner = method.owner;
      if (owner == null) continue;
      final ancestors = symbols.ancestorsByClass[owner] ?? const <String>[];
      for (final ancestor in ancestors) {
        final matches = symbols.callables.where(
          (candidate) =>
              candidate.owner == ancestor && candidate.name == method.name,
        );
        if (matches.isEmpty) continue;
        final parent = matches.first;
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.overrideImplementation,
            source: method.anchor,
            target: parent.anchor,
            description: '${method.displayName} override ${parent.displayName}',
          ),
        );
      }
    }
  }
}

enum _SymbolKind {
  function,
  method,
  constructor,
  getter,
  setter,
  variable,
  parameter,
}

class _LocalSymbol {
  const _LocalSymbol({
    required this.name,
    required this.kind,
    required this.anchor,
    required this.offset,
    required this.end,
    this.owner,
    this.constructorName,
    this.parameters = const <_LocalSymbol>[],
  });

  final String name;
  final _SymbolKind kind;
  final CodeRelationshipAnchor anchor;
  final int offset;
  final int end;
  final String? owner;
  final String? constructorName;
  final List<_LocalSymbol> parameters;

  String get displayName => owner == null ? name : '$owner.$name';
}

class _LocalSymbolCollector extends RecursiveAstVisitor<void> {
  _LocalSymbolCollector(this.source);

  final String source;
  final List<_LocalSymbol> callables = <_LocalSymbol>[];
  final List<_LocalSymbol> constructors = <_LocalSymbol>[];
  final List<_LocalSymbol> getters = <_LocalSymbol>[];
  final List<_LocalSymbol> setters = <_LocalSymbol>[];
  final List<_LocalSymbol> values = <_LocalSymbol>[];
  final Map<int, _LocalSymbol> valueByDeclarationOffset = <int, _LocalSymbol>{};
  final Map<String, List<String>> ancestorsByClass = <String, List<String>>{};
  final Set<int> declarationTokenOffsets = <int>{};

  int get declarationCount =>
      callables.length +
      constructors.length +
      getters.length +
      setters.length +
      values.length;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.name.lexeme;
    final ancestors = <String>[];
    final superclass = node.extendsClause?.superclass.toSource();
    if (superclass != null && superclass.isNotEmpty) {
      ancestors.add(_stripTypeArguments(superclass));
    }
    for (final interface
        in node.implementsClause?.interfaces ?? const <NamedType>[]) {
      ancestors.add(_stripTypeArguments(interface.toSource()));
    }
    ancestorsByClass[className] = ancestors;
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final token = node.name;
    declarationTokenOffsets.add(token.offset);
    final owner = _classOwnerOf(node);
    final parameters = _parameterSymbols(node.parameters, owner: owner);
    final kind = node.isGetter
        ? _SymbolKind.getter
        : node.isSetter
            ? _SymbolKind.setter
            : _SymbolKind.method;
    final symbol = _LocalSymbol(
      name: token.lexeme,
      kind: kind,
      anchor: _anchorForToken(source, token, token.lexeme),
      offset: node.offset,
      end: node.end,
      owner: owner,
      parameters: parameters,
    );
    switch (kind) {
      case _SymbolKind.getter:
        getters.add(symbol);
      case _SymbolKind.setter:
        setters.add(symbol);
      default:
        callables.add(symbol);
    }
    _addValues(parameters);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final token = node.name;
    declarationTokenOffsets.add(token.offset);
    final owner = _classOwnerOf(node);
    final parameters = _parameterSymbols(
      node.functionExpression.parameters,
      owner: owner,
    );
    final kind = node.propertyKeyword?.lexeme == 'get'
        ? _SymbolKind.getter
        : node.propertyKeyword?.lexeme == 'set'
            ? _SymbolKind.setter
            : _SymbolKind.function;
    final symbol = _LocalSymbol(
      name: token.lexeme,
      kind: kind,
      anchor: _anchorForToken(source, token, token.lexeme),
      offset: node.offset,
      end: node.end,
      owner: owner,
      parameters: parameters,
    );
    switch (kind) {
      case _SymbolKind.getter:
        getters.add(symbol);
      case _SymbolKind.setter:
        setters.add(symbol);
      default:
        callables.add(symbol);
    }
    _addValues(parameters);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final owner = _classOwnerOf(node);
    if (owner == null) {
      super.visitConstructorDeclaration(node);
      return;
    }

    final named = node.name?.lexeme;
    final headerEnd = node.parameters.offset.clamp(node.offset, source.length);
    final header = source.substring(node.offset, headerEnd);
    final needle = named ?? owner;
    final localNameOffset = header.lastIndexOf(needle);
    final nameOffset =
        localNameOffset < 0 ? node.offset : node.offset + localNameOffset;
    declarationTokenOffsets.add(nameOffset);

    final parameters = _parameterSymbols(node.parameters, owner: owner);
    final displayName = named == null ? owner : '$owner.$named';
    constructors.add(
      _LocalSymbol(
        name: owner,
        kind: _SymbolKind.constructor,
        anchor: _anchorForOffset(
          source,
          nameOffset,
          needle.length,
          displayName,
        ),
        offset: node.offset,
        end: node.end,
        owner: owner,
        constructorName: named,
        parameters: parameters,
      ),
    );
    _addValues(parameters);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final token = node.name;
    declarationTokenOffsets.add(token.offset);
    final symbol = _LocalSymbol(
      name: token.lexeme,
      kind: _SymbolKind.variable,
      anchor: _anchorForToken(source, token, token.lexeme),
      offset: node.offset,
      end: node.end,
      owner: _classOwnerOf(node),
    );
    values.add(symbol);
    valueByDeclarationOffset[token.offset] = symbol;
    super.visitVariableDeclaration(node);
  }

  void _addValues(Iterable<_LocalSymbol> symbols) {
    for (final symbol in symbols) {
      values.add(symbol);
      valueByDeclarationOffset[symbol.anchor.offset] = symbol;
    }
  }

  List<_LocalSymbol> _parameterSymbols(
    FormalParameterList? list, {
    required String? owner,
  }) {
    if (list == null) return const <_LocalSymbol>[];
    final result = <_LocalSymbol>[];
    for (final parameter in list.parameters) {
      final token = parameter.name;
      if (token == null) continue;
      declarationTokenOffsets.add(token.offset);
      result.add(
        _LocalSymbol(
          name: token.lexeme,
          kind: _SymbolKind.parameter,
          anchor: _anchorForToken(source, token, token.lexeme),
          offset: parameter.offset,
          end: parameter.end,
          owner: owner,
        ),
      );
    }
    return result;
  }

  _LocalSymbol? resolveCallable(
    String name, {
    required int useOffset,
    String? owner,
  }) {
    final candidates = callables.where((symbol) => symbol.name == name).toList();
    if (candidates.isEmpty) return null;
    if (owner != null) {
      final sameOwner = candidates.where((symbol) => symbol.owner == owner);
      if (sameOwner.isNotEmpty) return sameOwner.first;
    }
    if (candidates.length == 1) return candidates.single;
    candidates.sort(
      (a, b) =>
          (a.anchor.offset - useOffset).abs().compareTo(
                (b.anchor.offset - useOffset).abs(),
              ),
    );
    return candidates.first;
  }

  _LocalSymbol? resolveConstructor(String typeName, String? named) {
    final type = _stripTypeArguments(typeName);
    final candidates = constructors.where(
      (symbol) => symbol.owner == type && symbol.constructorName == named,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  _LocalSymbol? resolveGetter(String name, {required int useOffset}) =>
      _nearest(getters.where((symbol) => symbol.name == name), useOffset);

  _LocalSymbol? resolveSetter(String name, {required int useOffset}) =>
      _nearest(setters.where((symbol) => symbol.name == name), useOffset);

  _LocalSymbol? valueDeclaredAt(int declarationOffset) =>
      valueByDeclarationOffset[declarationOffset];

  _LocalSymbol? resolveValue(String name, {required int useOffset}) {
    final candidates = values.where(
      (symbol) => symbol.name == name && symbol.anchor.offset != useOffset,
    );
    final list = candidates.toList();
    if (list.isEmpty) return null;
    final before = list.where((symbol) => symbol.anchor.offset <= useOffset).toList();
    if (before.isNotEmpty) {
      before.sort((a, b) => b.anchor.offset.compareTo(a.anchor.offset));
      return before.first;
    }
    return _nearest(list, useOffset);
  }

  _LocalSymbol? _nearest(
    Iterable<_LocalSymbol> candidates,
    int useOffset,
  ) {
    final list = candidates.toList();
    if (list.isEmpty) return null;
    list.sort(
      (a, b) =>
          (a.anchor.offset - useOffset).abs().compareTo(
                (b.anchor.offset - useOffset).abs(),
              ),
    );
    return list.first;
  }
}

class _RelationshipCollector extends RecursiveAstVisitor<void> {
  _RelationshipCollector({
    required this.source,
    required this.symbols,
    required this.add,
  });

  final String source;
  final _LocalSymbolCollector symbols;
  final void Function(CodeRelationship relationship) add;
  final Map<String, _LocalSymbol> functionAliases = <String, _LocalSymbol>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final constructor = _constructorForMethodInvocation(node);
    if (constructor != null) {
      _addConstructorInvocation(
        invocation: node,
        argumentList: node.argumentList,
        constructor: constructor,
      );
      super.visitMethodInvocation(node);
      return;
    }

    final name = node.methodName.name;
    final callable = symbols.resolveCallable(
          name,
          useOffset: node.methodName.offset,
          owner: _classOwnerOf(node),
        ) ??
        functionAliases[name];
    if (callable != null) {
      _addCallableInvocation(
        invocation: node,
        nameOffset: node.methodName.offset,
        name: name,
        argumentList: node.argumentList,
        target: callable,
      );
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier) {
      final name = function.name;
      final callable = symbols.resolveCallable(
            name,
            useOffset: function.offset,
            owner: _classOwnerOf(node),
          ) ??
          functionAliases[name];
      if (callable != null) {
        _addCallableInvocation(
          invocation: node,
          nameOffset: function.offset,
          name: name,
          argumentList: node.argumentList,
          target: callable,
        );
      }
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructorName = node.constructorName;
    final typeName = constructorName.type.toSource();
    final named = constructorName.name?.name;
    final constructor = symbols.resolveConstructor(typeName, named);
    if (constructor != null) {
      _addConstructorInvocation(
        invocation: node,
        argumentList: node.argumentList,
        constructor: constructor,
      );
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer;
    final declared = symbols.valueDeclaredAt(node.name.offset);
    if (initializer != null && declared != null) {
      if (initializer is SimpleIdentifier) {
        final callable = symbols.resolveCallable(
          initializer.name,
          useOffset: initializer.offset,
          owner: _classOwnerOf(node),
        );
        if (callable != null) {
          functionAliases[node.name.lexeme] = callable;
          add(
            CodeRelationship(
              kind: CodeRelationshipKind.callback,
              source: _anchorForNode(source, initializer, initializer.name),
              target: callable.anchor,
              description: '${initializer.name} 引用 ${callable.displayName}',
            ),
          );
        }
      }

      if (!_containsLocalInvocation(initializer)) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.variableWrite,
            source: _anchorForNode(source, initializer, initializer.toSource()),
            target: declared.anchor,
            description: '${initializer.toSource()} 写入 ${declared.name}',
          ),
        );
      }
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final name = _assignableName(node.leftHandSide);
    if (name != null) {
      final target = symbols.resolveValue(name, useOffset: node.leftHandSide.offset);
      if (target != null && !_containsLocalInvocation(node.rightHandSide)) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.variableWrite,
            source: _anchorForNode(
              source,
              node.rightHandSide,
              node.rightHandSide.toSource(),
            ),
            target: target.anchor,
            description: '${node.rightHandSide.toSource()} 写入 $name',
          ),
        );
      }
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (symbols.declarationTokenOffsets.contains(node.offset) ||
        _isInvocationName(node)) {
      super.visitSimpleIdentifier(node);
      return;
    }

    final name = node.name;
    final write = _isWriteReference(node);

    if (write) {
      final setter = symbols.resolveSetter(name, useOffset: node.offset);
      if (setter != null) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.setterWrite,
            source: _anchorForNode(source, node, name),
            target: setter.anchor,
            description: '$name 写入 ${setter.displayName}',
          ),
        );
      }
    } else {
      final getter = symbols.resolveGetter(name, useOffset: node.offset);
      if (getter != null) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.getterRead,
            source: getter.anchor,
            target: _anchorForNode(source, node, name),
            description: '${getter.displayName} 提供 $name',
          ),
        );
      }
    }

    final callable = symbols.resolveCallable(
      name,
      useOffset: node.offset,
      owner: _classOwnerOf(node),
    );
    if (callable != null && _isFunctionReference(node)) {
      add(
        CodeRelationship(
          kind: CodeRelationshipKind.callback,
          source: _anchorForNode(source, node, name),
          target: callable.anchor,
          description: '$name 引用 ${callable.displayName}',
        ),
      );
    }

    final value = symbols.resolveValue(name, useOffset: node.offset);
    if (value != null && !write) {
      add(
        CodeRelationship(
          kind: CodeRelationshipKind.variableRead,
          source: value.anchor,
          target: _anchorForNode(source, node, name),
          description: '${value.name} 被读取',
        ),
      );
    }

    super.visitSimpleIdentifier(node);
  }

  _LocalSymbol? _constructorForMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target == null) {
      return symbols.resolveConstructor(node.methodName.name, null);
    }

    final targetText = target.toSource();
    return symbols.resolveConstructor(targetText, node.methodName.name);
  }

  void _addConstructorInvocation({
    required Expression invocation,
    required ArgumentList argumentList,
    required _LocalSymbol constructor,
  }) {
    add(
      CodeRelationship(
        kind: CodeRelationshipKind.constructor,
        source: _anchorForNode(
          source,
          invocation,
          invocation.toSource(),
        ),
        target: constructor.anchor,
        description: '${invocation.toSource()} 构造 ${constructor.displayName}',
      ),
    );
    _addArgumentFlows(argumentList, constructor);
    _addReturnReceiver(invocation, constructor);
  }

  void _addCallableInvocation({
    required Expression invocation,
    required int nameOffset,
    required String name,
    required ArgumentList argumentList,
    required _LocalSymbol target,
  }) {
    final caller = _enclosingCallable(node: invocation);
    final recursive = caller != null &&
        caller.name == target.name &&
        caller.owner == target.owner;
    add(
      CodeRelationship(
        kind: recursive
            ? CodeRelationshipKind.recursion
            : CodeRelationshipKind.call,
        source: _anchorForOffset(source, nameOffset, name.length, name),
        target: target.anchor,
        description: '$name ${recursive ? '递归调用' : '调用'} ${target.displayName}',
      ),
    );
    _addArgumentFlows(argumentList, target);
    _addReturnReceiver(invocation, target);
  }

  void _addArgumentFlows(ArgumentList arguments, _LocalSymbol target) {
    if (target.parameters.isEmpty) return;
    var positionalIndex = 0;
    for (final argument in arguments.arguments) {
      Expression expression = argument;
      String? namedLabel;
      if (argument is NamedExpression) {
        namedLabel = argument.name.label.name;
        expression = argument.expression;
      }

      _LocalSymbol? parameter;
      if (namedLabel != null) {
        final matches = target.parameters.where(
          (candidate) => candidate.name == namedLabel,
        );
        if (matches.isNotEmpty) parameter = matches.first;
      } else if (positionalIndex < target.parameters.length) {
        parameter = target.parameters[positionalIndex++];
      }
      if (parameter == null) continue;

      add(
        CodeRelationship(
          kind: CodeRelationshipKind.parameterFlow,
          source: _anchorForNode(source, expression, expression.toSource()),
          target: parameter.anchor,
          description: '${expression.toSource()} → 参数 ${parameter.name}',
        ),
      );
    }
  }

  void _addReturnReceiver(Expression invocation, _LocalSymbol target) {
    AstNode current = invocation;
    while (current.parent is AwaitExpression ||
        current.parent is ParenthesizedExpression) {
      current = current.parent!;
    }

    final parent = current.parent;
    if (parent is VariableDeclaration && identical(parent.initializer, current)) {
      final receiver = symbols.valueDeclaredAt(parent.name.offset);
      if (receiver != null) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.returnFlow,
            source: target.anchor,
            target: receiver.anchor,
            description: '${target.displayName} 返回值 → ${receiver.name}',
          ),
        );
      }
      return;
    }

    if (parent is AssignmentExpression && identical(parent.rightHandSide, current)) {
      final name = _assignableName(parent.leftHandSide);
      if (name == null) return;
      final receiver = symbols.resolveValue(name, useOffset: parent.leftHandSide.offset);
      if (receiver != null) {
        add(
          CodeRelationship(
            kind: CodeRelationshipKind.returnFlow,
            source: target.anchor,
            target: receiver.anchor,
            description: '${target.displayName} 返回值 → $name',
          ),
        );
      }
    }
  }

  bool _containsLocalInvocation(Expression expression) {
    final finder = _LocalInvocationFinder(symbols);
    expression.accept(finder);
    return finder.found;
  }
}

class _LocalInvocationFinder extends RecursiveAstVisitor<void> {
  _LocalInvocationFinder(this.symbols);

  final _LocalSymbolCollector symbols;
  bool found = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final constructor = target == null
        ? symbols.resolveConstructor(node.methodName.name, null)
        : symbols.resolveConstructor(target.toSource(), node.methodName.name);
    if (constructor != null ||
        symbols.resolveCallable(
              node.methodName.name,
              useOffset: node.methodName.offset,
              owner: _classOwnerOf(node),
            ) !=
            null) {
      found = true;
      return;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (symbols.resolveConstructor(
          node.constructorName.type.toSource(),
          node.constructorName.name?.name,
        ) !=
        null) {
      found = true;
      return;
    }
    super.visitInstanceCreationExpression(node);
  }
}

_LocalSymbol? _enclosingCallable({required AstNode node}) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is MethodDeclaration) {
      return _LocalSymbol(
        name: current.name.lexeme,
        kind: _SymbolKind.method,
        anchor: const CodeRelationshipAnchor(
          line: 0,
          column: 0,
          length: 0,
          offset: 0,
          label: '',
        ),
        offset: current.offset,
        end: current.end,
        owner: _classOwnerOf(current),
      );
    }
    if (current is FunctionDeclaration) {
      return _LocalSymbol(
        name: current.name.lexeme,
        kind: _SymbolKind.function,
        anchor: const CodeRelationshipAnchor(
          line: 0,
          column: 0,
          length: 0,
          offset: 0,
          label: '',
        ),
        offset: current.offset,
        end: current.end,
        owner: _classOwnerOf(current),
      );
    }
    current = current.parent;
  }
  return null;
}

bool _isInvocationName(SimpleIdentifier node) {
  final parent = node.parent;
  if (parent is MethodInvocation && identical(parent.methodName, node)) {
    return true;
  }
  if (parent is ConstructorName && identical(parent.name, node)) return true;
  return false;
}

bool _isFunctionReference(SimpleIdentifier node) {
  AstNode? current = node.parent;
  for (var depth = 0; current != null && depth < 4; depth++) {
    if (current is ArgumentList || current is NamedExpression) return true;
    if (current is VariableDeclaration || current is AssignmentExpression) {
      return true;
    }
    if (current is MethodInvocation || current is FunctionExpressionInvocation) {
      return false;
    }
    current = current.parent;
  }
  return false;
}

bool _isWriteReference(SimpleIdentifier node) {
  AstNode? current = node;
  for (var depth = 0; depth < 3 && current?.parent != null; depth++) {
    final parent = current!.parent!;
    if (parent is AssignmentExpression &&
        parent.leftHandSide.offset <= node.offset &&
        node.end <= parent.leftHandSide.end) {
      return true;
    }
    if (parent is PrefixExpression || parent is PostfixExpression) {
      final source = parent.toSource();
      if (source.contains('++') || source.contains('--')) return true;
    }
    current = parent;
  }
  return false;
}

String? _assignableName(Expression expression) {
  if (expression is SimpleIdentifier) return expression.name;
  if (expression is PropertyAccess) return expression.propertyName.name;
  if (expression is PrefixedIdentifier) return expression.identifier.name;
  return null;
}

String? _classOwnerOf(AstNode node) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is ClassDeclaration) return current.name.lexeme;
    current = current.parent;
  }
  return null;
}

String _stripTypeArguments(String source) {
  final genericStart = source.indexOf('<');
  final plain = genericStart < 0 ? source : source.substring(0, genericStart);
  return plain.trim().split('.').last;
}

CodeRelationshipAnchor _anchorForToken(
  String source,
  dynamic token,
  String label,
) {
  return _anchorForOffset(
    source,
    token.offset as int,
    (token.length as int).clamp(1, source.length).toInt(),
    label,
  );
}

CodeRelationshipAnchor _anchorForNode(
  String source,
  AstNode node,
  String label,
) {
  return _anchorForOffset(
    source,
    node.offset,
    node.length.clamp(1, source.length).toInt(),
    label,
  );
}

CodeRelationshipAnchor _anchorForOffset(
  String source,
  int offset,
  int length,
  String label,
) {
  final safeOffset = offset.clamp(0, source.length).toInt();
  var line = 1;
  var column = 1;
  for (var i = 0; i < safeOffset; i++) {
    if (source.codeUnitAt(i) == 10) {
      line++;
      column = 1;
    } else {
      column++;
    }
  }
  return CodeRelationshipAnchor(
    line: line,
    column: column,
    length: length,
    offset: safeOffset,
    label: label,
  );
}
