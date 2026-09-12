import '../../../core/errors/parse_exception.dart';
import '../../../core/l10n/app_localizations.dart';
import '../models/token.dart';

String _localized(String zh, String en) =>
    AppLocaleController.locale.value.languageCode == 'en' ? en : zh;

class Tokenizer {
  List<Token> tokenize(String source) {
    final out = <Token>[];
    var i = 0, line = 1, col = 1;
    bool end() => i >= source.length;
    void next() {
      if (source[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
      i++;
    }

    while (!end()) {
      final ch = source[i];
      if (ch.trim().isEmpty) {
        next();
        continue;
      }
      final sl = line, sc = col;
      if (ch == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (!end() && source[i] != '\n') {
          next();
        }
        continue;
      }
      if (ch == '/' && i + 1 < source.length && source[i + 1] == '*') {
        next();
        next();
        while (!end() &&
            !(source[i] == '*' &&
                i + 1 < source.length &&
                source[i + 1] == '/')) {
          next();
        }
        if (end()) {
          throw ParseException(
            _localized(
              '多行注释缺少 */',
              'The block comment is missing */',
            ),
            sl,
            sc,
            '/*',
          );
        }
        next();
        next();
        continue;
      }
      const marks = {
        '(': TokenType.leftParen,
        ')': TokenType.rightParen,
        '[': TokenType.leftBracket,
        ']': TokenType.rightBracket,
        ',': TokenType.comma,
        ':': TokenType.colon,
        '.': TokenType.dot,
      };
      if (marks[ch] != null) {
        out.add(Token(marks[ch]!, ch, line, col));
        next();
        continue;
      }
      if (ch == "'" || ch == '"') {
        final quote = ch;
        next();
        final value = StringBuffer();
        while (!end() && source[i] != quote) {
          if (source[i] == '\\') {
            next();
            if (end()) break;
            const escapes = {
              'n': '\n',
              'r': '\r',
              't': '\t',
              '\\': '\\',
              "'": "'",
              '"': '"',
            };
            value.write(escapes[source[i]] ?? source[i]);
            next();
          } else {
            value.write(source[i]);
            next();
          }
        }
        if (end()) {
          throw ParseException(
            _localized(
              '字符串缺少结束引号',
              'The string is missing a closing quote',
            ),
            sl,
            sc,
            quote,
          );
        }
        next();
        out.add(Token(TokenType.string, value.toString(), sl, sc));
        continue;
      }
      if (_digit(ch) ||
          (ch == '-' && i + 1 < source.length && _digit(source[i + 1]))) {
        final start = i;
        next();
        while (!end() && RegExp(r'[0-9a-fA-FxX.]').hasMatch(source[i])) {
          next();
        }
        out.add(Token(TokenType.number, source.substring(start, i), sl, sc));
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(ch)) {
        final start = i;
        while (!end() && RegExp(r'[A-Za-z0-9_]').hasMatch(source[i])) {
          next();
        }
        final word = source.substring(start, i);
        out.add(
          Token(
            word == 'true' || word == 'false'
                ? TokenType.boolean
                : word == 'null'
                    ? TokenType.nullValue
                    : TokenType.identifier,
            word,
            sl,
            sc,
          ),
        );
        continue;
      }
      throw ParseException(
        _localized(
          '无法识别的字符',
          'Unrecognized character',
        ),
        line,
        col,
        ch,
      );
    }
    out.add(Token(TokenType.eof, '', line, col));
    return out;
  }

  bool _digit(String s) => RegExp(r'[0-9]').hasMatch(s);
}
