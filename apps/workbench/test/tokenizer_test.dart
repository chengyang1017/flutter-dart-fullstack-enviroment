import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/models/token.dart';
import 'package:flutter_ui_playground/features/playground/parser/tokenizer.dart';

void main() {
  final tokenizer = Tokenizer();
  test('tokenizes strings numbers nesting and positions', () {
    final t = tokenizer.tokenize("Text('I\\'m', size: 12)");
    expect(
      t.map((e) => e.type),
      containsAll([TokenType.identifier, TokenType.string, TokenType.number]),
    );
    expect(t[0].line, 1);
    expect(t[0].column, 1);
    expect(t[2].lexeme, "I'm");
  });
  test('ignores line and block comments', () {
    final t = tokenizer.tokenize('// one\n/* two */ Text("ok")');
    expect(t.first.lexeme, 'Text');
    expect(t.first.line, 2);
  });
}
