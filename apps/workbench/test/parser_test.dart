import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/core/errors/parse_exception.dart';
import 'package:flutter_ui_playground/features/playground/models/ui_value.dart';
import 'package:flutter_ui_playground/features/playground/parser/flutter_ui_parser.dart';

void main() {
  final p = FlutterUiParser();
  test('Text', () {
    final n = p.parse("Text('Hello',)");
    expect(n.type, 'Text');
    expect((n.positionalArguments.first as StringUiValue).value, 'Hello');
  });
  test('nested Container and Column children', () {
    final n = p.parse(
      "Container(padding: EdgeInsets.all(16), child: Column(children: [Text('a'), SizedBox(height: 8),],),)",
    );
    expect((n.namedArguments['child'] as NodeUiValue).value.type, 'Column');
  });
  test(
    'unknown widgets remain nodes',
    () => expect(p.parse('ListView()').type, 'ListView'),
  );
  test(
    'missing parenthesis reports error',
    () => expect(() => p.parse("Text('x'"), throwsA(isA<ParseException>())),
  );
  test(
    'missing bracket reports error',
    () => expect(
      () => p.parse("Column(children:[Text('x'))"),
      throwsA(isA<ParseException>()),
    ),
  );
}
