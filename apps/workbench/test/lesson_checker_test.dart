import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/checking/lesson_checker.dart';
import 'package:flutter_ui_playground/features/lessons/models/lesson_requirement.dart';
import 'package:flutter_ui_playground/features/playground/models/ui_value.dart';

void main() {
  final checker = LessonChecker();

  test('识别存在的 Widget', () {
    final result = checker.check("Center(child: Text('Hello'))", [
      const RequiredWidgetRequirement('Center'),
    ]);
    expect(result.passed, isTrue);
  });

  test('正确统计 Widget 数量', () {
    final result = checker.check(
      "Column(children: [Text('一'), Text('二')])",
      [const RequiredWidgetCountRequirement('Text', 2)],
    );
    expect(result.passed, isTrue);
  });

  test('识别指定 Text 内容', () {
    final result = checker.check("Text('Glyphora')", [
      const RequiredTextRequirement('Glyphora'),
    ]);
    expect(result.passed, isTrue);
  });

  test('识别属性值', () {
    final result = checker.check('Container(color: Colors.blue)', [
      const RequiredPropertyRequirement(
        'Container',
        'color',
        IdentifierUiValue('Colors.blue'),
      ),
    ]);
    expect(result.passed, isTrue);
  });

  test('识别直接父子关系', () {
    final result = checker.check("Card(child: Text('资料'))", [
      const RequiredChildRelationshipRequirement('Card', 'Text'),
    ]);
    expect(result.passed, isTrue);
  });

  test('不同格式和参数顺序但结构相同可以通过', () {
    final requirements = [
      const RequiredWidgetRequirement('Container'),
      const RequiredPropertyRequirement(
        'Container',
        'color',
        IdentifierUiValue('Colors.blue'),
      ),
      const RequiredTextRequirement('Hello'),
    ];
    final compact = checker.check(
      "Container(color: Colors.blue, child: Text('Hello'))",
      requirements,
    );
    final reformatted = checker.check(
      """Container(
  child: Text("Hello"),
  color: Colors.blue,
)""",
      requirements,
    );
    expect(compact.passed, isTrue);
    expect(reformatted.passed, isTrue);
  });

  test('错误代码不能通过', () {
    final result = checker.check("Text('缺少括号'", [
      const RequiredWidgetRequirement('Text'),
    ]);
    expect(result.passed, isFalse);
    expect(result.parseError, isNotNull);
  });
}
