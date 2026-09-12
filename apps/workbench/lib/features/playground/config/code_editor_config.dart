import 'package:re_editor/re_editor.dart';

abstract final class CodeEditorConfig {
  /// 按一次 Tab 插入 4 個空格。
  static const lineOptions = CodeLineOptions(
    indentSize: 4,
  );

  /// Windows 上 VS Code 預設常用的等寬字體。
  static const String fontFamily = 'Consolas';

  /// 目前字體不存在時依序使用。
  static const List<String> fontFamilyFallback = [
    'Cascadia Code',
    'Cascadia Mono',
    'Courier New',
    'monospace',

    // 中文字符使用這個字體補足。
    'Microsoft YaHei',
  ];

  static const double fontSize = 16;
  static const double compactFontSize = 15;
  static const double fontHeight = 1.5;

  static const double lineNumberFontSize = 14;
}
