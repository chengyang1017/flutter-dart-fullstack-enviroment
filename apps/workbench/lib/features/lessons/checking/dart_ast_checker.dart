import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../models/lesson_requirement.dart';

class DartAstChecker {
  String? syntaxError(String code) {
    final direct = parseString(content: code, throwIfDiagnostics: false);
    if (direct.errors.isEmpty) return null;
    final wrapped = parseString(
      content: '''
class LessonSnippet {
  Future<void> snippet() async {
    $code
  }
}
''',
      throwIfDiagnostics: false,
    );
    if (wrapped.errors.isEmpty) return null;
    return wrapped.errors.first.toString();
  }

  bool check(String code, LessonRequirement requirement) {
    final unit = _parseBestEffort(code);
    final facts = _DartFacts()..collect(unit);
    return switch (requirement) {
      RequiredClassRequirement r => facts.classes.contains(r.className),
      RequiredFieldRequirement r => facts.fields.contains(r.fieldName),
      RequiredMethodRequirement r => facts.methods.contains(r.methodName),
      RequiredMethodCallRequirement r => facts.calls.contains(r.methodName),
      RequiredAwaitRequirement _ => facts.hasAwait,
      RequiredIfRequirement _ => facts.hasIf,
      RequiredTrimRequirement _ => facts.calls.contains('trim'),
      RequiredCurrentUserRequirement _ =>
        facts.properties.contains('currentUser'),
      RequiredCollectionRequirement r =>
        facts.collections.contains(r.collection),
      RequiredMapFieldsRequirement r => r.fields.every(facts.mapKeys.contains),
      RequiredServerTimestampRequirement _ =>
        facts.calls.contains('FieldValue.serverTimestamp'),
      RequiredCodeIdentifierRequirement r =>
        facts.identifiers.contains(r.identifier),
      RequiredIntegerLiteralRequirement r => facts.integers.contains(r.value),
      RequiredRethrowRequirement _ => facts.hasRethrow,
      _ => false,
    };
  }

  CompilationUnit _parseBestEffort(String code) {
    final direct = parseString(content: code, throwIfDiagnostics: false);
    if (direct.errors.isEmpty) return direct.unit;
    final wrapped = '''
class LessonSnippet {
  Future<void> snippet() async {
    $code
  }
}
''';
    return parseString(content: wrapped, throwIfDiagnostics: false).unit;
  }
}

class _DartFacts extends RecursiveAstVisitor<void> {
  final classes = <String>{};
  final fields = <String>{};
  final methods = <String>{};
  final calls = <String>{};
  final properties = <String>{};
  final collections = <String>{};
  final mapKeys = <String>{};
  final identifiers = <String>{};
  final integers = <int>{};
  bool hasAwait = false;
  bool hasIf = false;
  bool hasRethrow = false;

  void collect(CompilationUnit unit) => unit.accept(this);

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    classes.add(node.name.lexeme);
    super.visitClassDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final parent = node.parent?.parent;
    if (parent is FieldDeclaration || parent is TopLevelVariableDeclaration) {
      fields.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    identifiers.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    final value = node.value;
    if (value != null) integers.add(value);
    super.visitIntegerLiteral(node);
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    hasRethrow = true;
    super.visitRethrowExpression(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    methods.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    methods.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    calls.add(name);
    if (node.target case PrefixedIdentifier target) {
      calls.add('${target.prefix.name}.${target.identifier.name}.$name');
    } else if (node.target case SimpleIdentifier target) {
      calls.add('${target.name}.$name');
    }
    if (name == 'collection') {
      final argument = node.argumentList.arguments.firstOrNull;
      if (argument is StringLiteral) {
        final value = argument.stringValue;
        if (value != null) collections.add(value);
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    properties.add(node.propertyName.name);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    properties.add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitAwaitExpression(AwaitExpression node) {
    hasAwait = true;
    super.visitAwaitExpression(node);
  }

  @override
  void visitIfStatement(IfStatement node) {
    hasIf = true;
    super.visitIfStatement(node);
  }

  @override
  void visitSetOrMapLiteral(SetOrMapLiteral node) {
    for (final element in node.elements.whereType<MapLiteralEntry>()) {
      if (element.key case StringLiteral key) {
        final value = key.stringValue;
        if (value != null) mapKeys.add(value);
      }
    }
    super.visitSetOrMapLiteral(node);
  }
}
