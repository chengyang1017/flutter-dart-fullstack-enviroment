import '../../../core/errors/parse_exception.dart';
import '../models/token.dart';

class ParserCursor {
  ParserCursor(this.tokens);
  final List<Token> tokens;
  int index = 0;
  Token get current => tokens[index];
  bool check(TokenType t) => current.type == t;
  Token advance() => tokens[index++];
  bool match(TokenType t) {
    if (!check(t)) return false;
    advance();
    return true;
  }

  Token expect(TokenType t, String message) {
    if (check(t)) return advance();
    throw ParseException(message, current.line, current.column, current.lexeme);
  }
}
