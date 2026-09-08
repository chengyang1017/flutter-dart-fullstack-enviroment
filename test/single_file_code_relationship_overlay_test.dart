import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/playground/services/single_file_code_relationship_analyzer.dart';
import 'package:flutter_ui_playground/features/playground/widgets/code_editor_panel.dart';

void main() {
  const source = '''
class BaseService {
  void save(int value) {}
}

class Repo {
  Repo();

  int _count = 0;

  int get count => _count;

  set count(int value) {
    _count = value;
  }

  int load(int input) {
    return input + _count;
  }
}

class App extends BaseService {
  final Repo repo = Repo();

  @override
  void save(int value) {
    final result = calculate(value);
    repo.count = result;
    print(repo.count);
  }

  int calculate(int input) {
    return helper(input);
  }

  int helper(int value) {
    if (value <= 0) return 0;
    return helper(value - 1);
  }

  void bind() {
    final callback = save;
    callback(1);
  }
}
''';

  test('single-file analysis connects real local code relationships', () {
    const analyzer = SingleFileCodeRelationshipAnalyzer();
    final result = analyzer.analyze(source: source);
    final kinds = result.relationships.map((item) => item.kind).toSet();

    expect(kinds, contains(CodeRelationshipKind.call));
    expect(kinds, contains(CodeRelationshipKind.recursion));
    expect(kinds, contains(CodeRelationshipKind.callback));
    expect(kinds, contains(CodeRelationshipKind.constructor));
    expect(kinds, contains(CodeRelationshipKind.getterRead));
    expect(kinds, contains(CodeRelationshipKind.setterWrite));
    expect(kinds, contains(CodeRelationshipKind.variableRead));
    expect(kinds, contains(CodeRelationshipKind.variableWrite));
    expect(kinds, contains(CodeRelationshipKind.parameterFlow));
    expect(kinds, contains(CodeRelationshipKind.returnFlow));
    expect(kinds, contains(CodeRelationshipKind.overrideImplementation));

    // print() is from the SDK and has no declaration in this source file.
    expect(
      result.relationships.where((item) => item.description.contains('print')),
      isEmpty,
    );
  });

  testWidgets('wire mode renders relationships directly over the real editor', (
    tester,
  ) async {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);
    controller.textController.text = source;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 620,
            child: CodeEditorPanel(
              controller: controller,
              wireModeEnabled: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
      find.byKey(const ValueKey('code-relationship-overlay')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('code-relationship-wire-layer')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('code-relationship-count')), findsOneWidget);
  });
}
