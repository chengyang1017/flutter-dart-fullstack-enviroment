class CodeReference {
  const CodeReference({
    required this.fileName,
    required this.line,
    required this.column,
    required this.lineText,
    required this.isDefinition,
    required this.isStandardAnswer,
    required this.stepIndex,
    this.sourceCode,
  });

  final String fileName;

  /// 从 1 开始的行号。
  final int line;

  /// 从 1 开始的列号。
  final int column;

  /// 引用所在行的代码。
  final String lineText;

  /// 是否为 class、enum、mixin 等定义位置。
  final bool isDefinition;

  /// true 表示结果来自课程作者标准答案。
  final bool isStandardAnswer;

  /// 结果所属的课程步骤索引。
  final int stepIndex;

  /// 标准答案的完整代码，用于点击结果后只读查看。
  ///
  /// 学生代码结果不需要保存这一项。
  final String? sourceCode;
}
