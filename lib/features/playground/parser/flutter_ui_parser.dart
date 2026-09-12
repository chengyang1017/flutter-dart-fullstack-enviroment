import '../../../core/errors/parse_exception.dart';
import '../../../core/l10n/app_localizations.dart';
import '../models/token.dart';
import '../models/ui_node.dart';
import '../models/ui_value.dart';
import 'parser_cursor.dart';
import 'tokenizer.dart';

String _localized(String zh, String en) =>
    AppLocaleController.locale.value.languageCode == 'en' ? en : zh;

class FlutterUiParser {
  UiNode parse(String source) {
    final c = ParserCursor(Tokenizer().tokenize(source));
    final v = _value(c);

    if (v is! NodeUiValue) {
      throw ParseException(
        _localized(
          '根元素必须是 Widget',
          'The root element must be a Widget',
        ),
        c.current.line,
        c.current.column,
        c.current.lexeme,
      );
    }

    c.expect(
      TokenType.eof,
      _localized(
        'Widget 后存在多余内容',
        'Unexpected content after the Widget',
      ),
    );
    return v.value;
  }

  UiValue _value(ParserCursor c) {
    // 支持 const Text(...)、const EdgeInsets.all(...)、const [...]。
    // 这里只忽略 const，不实现 Dart 真正的编译期常量语义。
    if (c.check(TokenType.identifier) && c.current.lexeme == 'const') {
      c.advance();
      return _value(c);
    }

    if (c.match(TokenType.string)) {
      return StringUiValue(c.tokens[c.index - 1].lexeme);
    }

    if (c.match(TokenType.number)) {
      final r = c.tokens[c.index - 1].lexeme;

      return NumberUiValue(
        r.toLowerCase().startsWith('0x')
            ? int.parse(r.substring(2), radix: 16)
            : num.parse(r),
      );
    }

    if (c.match(TokenType.boolean)) {
      return BooleanUiValue(
        c.tokens[c.index - 1].lexeme == 'true',
      );
    }

    if (c.match(TokenType.nullValue)) {
      return const NullUiValue();
    }

    if (c.match(TokenType.leftBracket)) {
      final values = <UiValue>[];

      while (!c.check(TokenType.rightBracket)) {
        if (c.check(TokenType.eof)) {
          throw ParseException(
            _localized(
              'children 列表缺少右方括号 ]',
              'The children list is missing a closing bracket ]',
            ),
            c.current.line,
            c.current.column,
            c.current.lexeme,
          );
        }

        values.add(_value(c));

        if (!c.match(TokenType.comma) && !c.check(TokenType.rightBracket)) {
          c.expect(
            TokenType.comma,
            _localized(
              '列表元素之间需要逗号',
              'List elements must be separated by commas',
            ),
          );
        }
      }

      c.advance();
      return ListUiValue(values);
    }

    final first = c.expect(
      TokenType.identifier,
      _localized('此处需要值', 'A value is required here'),
    );

    final name = StringBuffer(first.lexeme);

    while (c.match(TokenType.dot)) {
      name.write(
        '.${c.expect(
          TokenType.identifier,
          _localized('点号后需要标识符', 'An identifier is required after the dot'),
        ).lexeme}',
      );
    }

    if (!c.match(TokenType.leftParen)) {
      return IdentifierUiValue(name.toString());
    }

    final positional = <UiValue>[];
    final named = <String, UiValue>{};

    while (!c.check(TokenType.rightParen)) {
      if (c.check(TokenType.eof)) {
        throw ParseException(
          _localized(
            '${name.toString()} 缺少右括号 )',
            '${name.toString()} is missing a closing parenthesis )',
          ),
          c.current.line,
          c.current.column,
          c.current.lexeme,
        );
      }

      if (c.check(TokenType.identifier) &&
          c.tokens[c.index + 1].type == TokenType.colon) {
        final key = c.advance().lexeme;
        c.advance();

        named[key] = _value(c);
      } else {
        positional.add(_value(c));
      }

      if (!c.match(TokenType.comma) && !c.check(TokenType.rightParen)) {
        c.expect(
          TokenType.comma,
          _localized(
            '参数之间需要逗号',
            'Arguments must be separated by commas',
          ),
        );
      }
    }

    c.advance();

    return NodeUiValue(
      UiNode(
        type: name.toString(),
        positionalArguments: positional,
        namedArguments: named,
      ),
    );
  }
}
