enum TokenType {
  identifier,
  string,
  number,
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  comma,
  colon,
  dot,
  boolean,
  nullValue,
  eof,
}

class Token {
  const Token(this.type, this.lexeme, this.line, this.column);
  final TokenType type;
  final String lexeme;
  final int line, column;
}
