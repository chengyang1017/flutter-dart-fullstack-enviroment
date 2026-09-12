import 'package:flutter/material.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/re_highlight.dart';

/// 在 Dart 原始規則上，額外辨識：
///
/// 1. 大寫開頭的型別、Widget、類別
/// 2. 小寫開頭並帶括號的函數、方法
///
/// 不強制染色所有變數和屬性，讓普通變量在深淺主題中都保持高可讀性。
final Mode flutterDartMode = langDart.copyWith(
  Mode(
    name: 'Flutter Dart',
    contains: <Mode>[
      Mode(
        scope: 'type',
        match: r'\b[A-Z][A-Za-z0-9_]*\b',
        relevance: 0,
      ),
      Mode(
        scope: 'function',
        match:
            r'\b(?!if\b|for\b|while\b|switch\b|catch\b|assert\b|return\b|throw\b|this\b|super\b|new\b)[a-z_][A-Za-z0-9_]*(?=\s*\()',
        relevance: 0,
      ),
      ...List<Mode>.from(
        langDart.contains as List,
      ),
    ],
  ),
);

const TextStyle _darkNormal = TextStyle(color: Color(0xffd6deeb));
const TextStyle _darkKeyword = TextStyle(
  color: Color(0xffff7ab2),
  fontWeight: FontWeight.w500,
);
const TextStyle _darkType = TextStyle(color: Color(0xff7fdbff));
const TextStyle _darkFunction = TextStyle(color: Color(0xffffd580));
const TextStyle _darkConstant = TextStyle(color: Color(0xffb8e994));
const TextStyle _darkString = TextStyle(color: Color(0xfff6bd8a));
const TextStyle _darkParameter = TextStyle(color: Color(0xff82aaff));
const TextStyle _darkComment = TextStyle(
  color: Color(0xff7f9f7f),
  fontStyle: FontStyle.italic,
);
const TextStyle _darkAnnotation = TextStyle(color: Color(0xffc792ea));

const TextStyle _lightNormal = TextStyle(color: Color(0xff1f2937));
const TextStyle _lightKeyword = TextStyle(
  color: Color(0xffaf005f),
  fontWeight: FontWeight.w500,
);
const TextStyle _lightType = TextStyle(color: Color(0xff006f8a));
const TextStyle _lightFunction = TextStyle(color: Color(0xff8a5a00));
const TextStyle _lightConstant = TextStyle(color: Color(0xff3b6d16));
const TextStyle _lightString = TextStyle(color: Color(0xffa31515));
const TextStyle _lightParameter = TextStyle(color: Color(0xff245ea8));
const TextStyle _lightComment = TextStyle(
  color: Color(0xff56812a),
  fontStyle: FontStyle.italic,
);
const TextStyle _lightAnnotation = TextStyle(color: Color(0xff7a3e9d));

const Map<String, TextStyle> vscodeDark2026Theme = <String, TextStyle>{
  'root': TextStyle(
    color: Color(0xffd6deeb),
    backgroundColor: Color(0xff111318),
  ),
  'variable': _darkNormal,
  'variable.other': _darkNormal,
  'property': _darkNormal,
  'attr': _darkParameter,
  'attribute': _darkParameter,
  'params': _darkParameter,
  'keyword': _darkKeyword,
  'storage': _darkKeyword,
  'literal': _darkKeyword,
  'operator': _darkNormal,
  'type': _darkType,
  'built_in': _darkType,
  'class': _darkType,
  'title.class': _darkType,
  'title.class.inherited': _darkType,
  'function': _darkFunction,
  'title': _darkFunction,
  'title.function': _darkFunction,
  'title.function.invoke': _darkFunction,
  'constant': _darkConstant,
  'symbol': _darkConstant,
  'variable.language': _darkConstant,
  'number': _darkConstant,
  'string': _darkString,
  'meta-string': _darkString,
  'subst': _darkParameter,
  'template-variable': _darkParameter,
  'comment': _darkComment,
  'quote': _darkComment,
  'doctag': _darkComment,
  'meta': _darkAnnotation,
  'meta-keyword': _darkAnnotation,
  'punctuation': _darkNormal,
};

const Map<String, TextStyle> vscodeLight2026Theme = <String, TextStyle>{
  'root': TextStyle(
    color: Color(0xff1f2937),
    backgroundColor: Color(0xffffffff),
  ),
  'variable': _lightNormal,
  'variable.other': _lightNormal,
  'property': _lightNormal,
  'attr': _lightParameter,
  'attribute': _lightParameter,
  'params': _lightParameter,
  'keyword': _lightKeyword,
  'storage': _lightKeyword,
  'literal': _lightKeyword,
  'operator': _lightNormal,
  'type': _lightType,
  'built_in': _lightType,
  'class': _lightType,
  'title.class': _lightType,
  'title.class.inherited': _lightType,
  'function': _lightFunction,
  'title': _lightFunction,
  'title.function': _lightFunction,
  'title.function.invoke': _lightFunction,
  'constant': _lightConstant,
  'symbol': _lightConstant,
  'variable.language': _lightConstant,
  'number': _lightConstant,
  'string': _lightString,
  'meta-string': _lightString,
  'subst': _lightParameter,
  'template-variable': _lightParameter,
  'comment': _lightComment,
  'quote': _lightComment,
  'doctag': _lightComment,
  'meta': _lightAnnotation,
  'meta-keyword': _lightAnnotation,
  'punctuation': _lightNormal,
};
