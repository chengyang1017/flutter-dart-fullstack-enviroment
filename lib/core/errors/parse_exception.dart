import '../l10n/app_localizations.dart';

class ParseException implements Exception {
  const ParseException(this.message, this.line, this.column, [this.token]);

  final String message;
  final int line, column;
  final String? token;

  @override
  String toString() {
    final english = AppLocaleController.locale.value.languageCode == 'en';
    if (english) {
      return 'Parse failed: line $line, column $column\n'
          '$message${token == null ? '' : '\nNear token: $token'}';
    }
    return '解析失败：第 $line 行，第 $column 列\n'
        '$message${token == null ? '' : '\n附近 Token：$token'}';
  }
}
