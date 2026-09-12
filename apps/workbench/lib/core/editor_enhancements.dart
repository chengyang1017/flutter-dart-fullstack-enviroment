/// 代码编辑器增强配置
/// 
/// 该配置文件提供编辑器的增强功能支持，包括：
/// - 快捷键定义
/// - 语言特定设置  
/// - 主题和样式
/// - 自动补全规则
/// - 代码诊断配置

class EditorEnhancements {
  EditorEnhancements._();

  // ============================================================================
  // 快捷键定义 - Keyboard Shortcuts
  // ============================================================================

  /// 代码编辑快捷键映射
  static const Map<String, String> keyboardShortcuts = {
    // 代码编辑
    'format': 'Ctrl+Shift+F (Win/Linux) or Cmd+Shift+F (Mac)',
    'undo': 'Ctrl+Z (Win/Linux) or Cmd+Z (Mac)',
    'redo': 'Ctrl+Y (Win/Linux) or Cmd+Shift+Z (Mac)',
    'comment': 'Ctrl+/ (Win/Linux) or Cmd+/ (Mac)',
    'duplicate_line': 'Ctrl+D (Win/Linux) or Cmd+D (Mac)',
    'delete_line': 'Ctrl+Shift+K (Win/Linux) or Cmd+Shift+K (Mac)',
    'move_line_up': 'Alt+Up (Win/Linux) or Opt+Up (Mac)',
    'move_line_down': 'Alt+Down (Win/Linux) or Opt+Down (Mac)',

    // 搜索和替换
    'find': 'Ctrl+F (Win/Linux) or Cmd+F (Mac)',
    'replace': 'Ctrl+H (Win/Linux) or Cmd+H (Mac)',
    'find_next': 'F3 or Ctrl+G (Win/Linux) or Cmd+G (Mac)',

    // 代码导航
    'go_to_line': 'Ctrl+G (Win/Linux) or Cmd+G (Mac)',
    'go_to_definition': 'Ctrl+Click or F12',
    'go_back': 'Alt+Left (Win/Linux) or Cmd+Left (Mac)',
    'go_forward': 'Alt+Right (Win/Linux) or Cmd+Right (Mac)',

    // 代码片段和自动补全
    'autocomplete': 'Ctrl+Space or Tab',
    'snippet_next': 'Tab',
    'snippet_previous': 'Shift+Tab',

    // 文件操作
    'save': 'Ctrl+S (Win/Linux) or Cmd+S (Mac)',
    'save_all': 'Ctrl+Shift+S (Win/Linux) or Cmd+Shift+S (Mac)',
  };

  // ============================================================================
  // 语言设置 - Language Settings
  // ============================================================================

  /// Dart 特定编辑器设置
  static const Map<String, dynamic> dartEditorSettings = {
    'indentSize': 2,
    'indentStyle': 'spaces',
    'insertSpaces': true,
    'trimTrailingWhitespace': true,
    'insertFinalNewline': true,
    'trimFinalNewlines': true,

    // 代码折叠
    'editor.foldingStrategy': 'indentation',

    // 代码补全
    'editor.autocomplete': true,
    'editor.autocompleteTrigger': ['>', '.', '(', '[', '{'],

    // 代码诊断
    'editor.showDiagnostics': true,
    'editor.diagnosticsDelay': 500,

    // 代码格式化
    'editor.formatOnSave': false,
    'editor.formatOnPaste': true,
    'editor.formatOnType': false,

    // 代码建议
    'editor.suggestOnTriggerCharacters': true,
    'editor.acceptSuggestionOnCommitCharacter': true,
    'editor.acceptSuggestionOnEnter': 'on',
  };

  /// 常见 Dart 代码片段
  static const List<CodeSnippet> dartSnippets = [
    CodeSnippet(
      label: 'class',
      description: '创建一个新的类',
      snippet: '''class \${1:ClassName} {
  \${2:// 类体}
}''',
    ),
    CodeSnippet(
      label: 'widget',
      description: '创建一个 StatelessWidget',
      snippet: '''class \${1:MyWidget} extends StatelessWidget {
  const \${1:MyWidget}({super.key});

  @override
  Widget build(BuildContext context) {
    return \${2:Container()};
  }
}''',
    ),
    CodeSnippet(
      label: 'stateful',
      description: '创建一个 StatefulWidget',
      snippet: '''class \${1:MyWidget} extends StatefulWidget {
  const \${1:MyWidget}({super.key});

  @override
  State<\${1:MyWidget}> createState() => _\${1:MyWidget}State();
}

class _\${1:MyWidget}State extends State<\${1:MyWidget}> {
  @override
  Widget build(BuildContext context) {
    return \${2:Container()};
  }
}''',
    ),
    CodeSnippet(
      label: 'future',
      description: '创建一个异步函数',
      snippet: '''Future<\${1:void}> \${2:functionName}() async {
  \${3:// 函数体}
}''',
    ),
    CodeSnippet(
      label: 'stream',
      description: '创建一个 Stream 函数',
      snippet: '''Stream<\${1:T}> \${2:functionName}() async* {
  \${3:// 函数体}
}''',
    ),
    CodeSnippet(
      label: 'test',
      description: '创建一个单元测试',
      snippet: '''test('\${1:test description}', () {
  \${2:// 测试代码}
});''',
    ),
  ];

  // ============================================================================
  // 主题和样式 - Themes and Styles
  // ============================================================================

  /// 编辑器主题配置
  static const Map<String, String> editorThemes = {
    'light': 'Light Theme (高对比度适合白天)',
    'dark': 'Dark Theme (护眼适合长时间编码)',
    'high-contrast': 'High Contrast (高可达性)',
    'solarized': 'Solarized (护眼)', 
  };

  /// 语法高亮颜色
  static const Map<String, String> syntaxHighlighting = {
    'keyword': '#FF7B00',        // 关键字 - 橙色
    'string': '#00B33C',         // 字符串 - 绿色
    'comment': '#808080',        // 注释 - 灰色
    'number': '#0066FF',         // 数字 - 蓝色
    'function': '#7B3FF2',        // 函数 - 紫色
    'class': '#FF0099',           // 类 - 红紫色
    'variable': '#3366FF',        // 变量 - 蓝色
  };

  // ============================================================================
  // 自动补全规则 - Autocomplete Rules
  // ============================================================================

  /// 常见的 Dart 自动补全建议
  static const List<CompletionItem> dartCompletions = [
    // 控制流
    CompletionItem(
      label: 'if',
      kind: 'keyword',
      snippet: 'if (\${1:condition}) {\n  \${2:}\n}',
    ),
    CompletionItem(
      label: 'for',
      kind: 'keyword',
      snippet: 'for (var i = 0; i < \${1:count}; i++) {\n  \${2:}\n}',
    ),
    CompletionItem(
      label: 'while',
      kind: 'keyword',
      snippet: 'while (\${1:condition}) {\n  \${2:}\n}',
    ),
    CompletionItem(
      label: 'try',
      kind: 'keyword',
      snippet: 'try {\n  \${1:}\n} catch (e) {\n  \${2:}\n}',
    ),

    // Flutter 常用 Widget
    CompletionItem(
      label: 'Container',
      kind: 'class',
      snippet: 'Container(\n  \${1:// 属性}\n)',
    ),
    CompletionItem(
      label: 'Column',
      kind: 'class',
      snippet: 'Column(\n  children: [\n    \${1:// 子元素}\n  ],\n)',
    ),
    CompletionItem(
      label: 'Row',
      kind: 'class',
      snippet: 'Row(\n  children: [\n    \${1:// 子元素}\n  ],\n)',
    ),
    CompletionItem(
      label: 'Text',
      kind: 'class',
      snippet: "Text('\${1:text}')",
    ),
    CompletionItem(
      label: 'Button',
      kind: 'class',
      snippet: 'ElevatedButton(\n  onPressed: () => \${1:},\n  child: Text('\${2:label}'),\n)',
    ),
  ];

  // ============================================================================
  // 诊断规则 - Diagnostic Rules
  // ============================================================================

  /// 代码诊断规则
  static const List<DiagnosticRule> diagnosticRules = [
    DiagnosticRule(
      id: 'unused-variable',
      severity: 'warning',
      message: '变量已声明但从未使用',
      pattern: r'(var|final|const)\s+(\w+)(?!.*\2)',
    ),
    DiagnosticRule(
      id: 'null-safety',
      severity: 'error',
      message: '可能的空指针异常，使用 ? 或 ! 操作符',
      pattern: r'(\w+)\.(\w+)\(',
    ),
    DiagnosticRule(
      id: 'long-line',
      severity: 'info',
      message: '代码行过长 (> 120 字符)',
      pattern: r'.{120,}',
    ),
    DiagnosticRule(
      id: 'missing-doc',
      severity: 'info',
      message: '公开函数/类缺少文档注释',
      pattern: r'(class|public\s+\w+|void|Future)\s+(\w+)',
    ),
  ];

  // ============================================================================
  // 性能优化 - Performance
  // ============================================================================

  /// 编辑器性能配置
  static const Map<String, dynamic> performanceSettings = {
    'maxTokenizationLineLength': 20000,
    'tokenizationSideSideTagsEnabled': false,
    'maxBasicCachingFileSize': 5242880, // 5MB
    'bracketPairColorization': {
      'enabled': true,
      'independentColorPoolPerBracketType': false,
    },
    'inlineSuggest': {
      'enabled': true,
      'showInlineCompletions': true,
      'suppressSuggestions': false,
    },
  };
}

// ============================================================================
// 数据类
// ============================================================================

/// 代码片段定义
class CodeSnippet {
  const CodeSnippet({
    required this.label,
    required this.description,
    required this.snippet,
  });

  final String label;
  final String description;
  final String snippet;
}

/// 代码补全项
class CompletionItem {
  const CompletionItem({
    required this.label,
    required this.kind,
    required this.snippet,
  });

  final String label;
  final String kind; // keyword, class, function, variable, etc
  final String snippet;
}

/// 代码诊断规则
class DiagnosticRule {
  const DiagnosticRule({
    required this.id,
    required this.severity,
    required this.message,
    required this.pattern,
  });

  final String id;
  final String severity; // error, warning, info
  final String message;
  final String pattern;
}
