import 'package:flutter/material.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/re_highlight.dart';

/// 在 Dart 原始規則上，額外辨識：
///
/// 1. 大寫開頭的型別、Widget、類別
/// 2. 小寫開頭並帶括號的函數、方法
///
/// 不強制染色所有變數和屬性，因為 VS Code Dark 2026
/// 本來就讓普通變數保持接近白色。
final Mode flutterDartMode = langDart.copyWith(
  Mode(
    name: 'Flutter Dart',
    contains: <Mode>[
      // 類別、Widget、型別：
      //
      // PlaygroundController
      // ChangeNotifier
      // PreviewDevice
      // String
      // Container
      Mode(
        scope: 'type',
        match: r'\b[A-Z][A-Za-z0-9_]*\b',
        relevance: 0,
      ),

      // 函數、方法：
      //
      // togglePreviewTheme(
      // notifyListeners(
      // contains(
      // add(
      Mode(
        scope: 'function',
        match:
            r'\b(?!if\b|for\b|while\b|switch\b|catch\b|assert\b|return\b|throw\b|this\b|super\b|new\b)[a-z_][A-Za-z0-9_]*(?=\s*\()',
        relevance: 0,
      ),

      // 保留 Dart 原有的關鍵字、字串、註釋、
      // 數字、Annotation 等規則。
      ...List<Mode>.from(
        langDart.contains as List,
      ),
    ],
  ),
);

const TextStyle _normal = TextStyle(
  color: Color(0xffd6deeb),
);

const TextStyle _keyword = TextStyle(
  color: Color(0xffff7ab2),
  fontWeight: FontWeight.w500,
);

const TextStyle _type = TextStyle(
  color: Color(0xff7fdbff),
);

const TextStyle _function = TextStyle(
  color: Color(0xffffd580),
);

const TextStyle _constant = TextStyle(
  color: Color(0xffb8e994),
);

const TextStyle _string = TextStyle(
  color: Color(0xfff6bd8a),
);

const TextStyle _parameter = TextStyle(
  color: Color(0xff82aaff),
);

const TextStyle _comment = TextStyle(
  color: Color(0xff7f9f7f),
  fontStyle: FontStyle.italic,
);

const TextStyle _annotation = TextStyle(
  color: Color(0xffc792ea),
);

/// 名称保持不变。
const Map<String, TextStyle> vscodeDark2026Theme = <String, TextStyle>{
  // 普通文字、局部变量、对象属性
  'root': TextStyle(
    color: Color(0xffd6deeb),
    backgroundColor: Color(0xff111318),
  ),
  'variable': _normal,
  'variable.other': _normal,
  'property': _normal,

  // named parameter
  'attr': _parameter,
  'attribute': _parameter,
  'params': _parameter,

  // class、void、extends、if、return、final
  'keyword': _keyword,
  'storage': _keyword,
  'literal': _keyword,
  'operator': _normal,

  // Widget、类、类型
  'type': _type,
  'built_in': _type,
  'class': _type,
  'title.class': _type,
  'title.class.inherited': _type,

  // 函数和方法
  'function': _function,
  'title': _function,
  'title.function': _function,
  'title.function.invoke': _function,

  // 常量、enum、布尔值
  'constant': _constant,
  'symbol': _constant,
  'variable.language': _constant,

  // 数字
  'number': _constant,

  // 字符串
  'string': _string,
  'meta-string': _string,

  // 字符串插值
  'subst': _parameter,
  'template-variable': _parameter,

  // 注释
  'comment': _comment,
  'quote': _comment,
  'doctag': _comment,

  // @override 等标记
  'meta': _annotation,
  'meta-keyword': _annotation,

  // 标点
  'punctuation': _normal,
};
