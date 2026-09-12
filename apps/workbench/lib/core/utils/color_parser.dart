import 'package:flutter/material.dart';
import '../../features/playground/models/ui_value.dart';

abstract final class ColorParser {
  static const _colors = <String, Color>{
    'Colors.red': Colors.red,
    'Colors.blue': Colors.blue,
    'Colors.green': Colors.green,
    'Colors.orange': Colors.orange,
    'Colors.purple': Colors.purple,
    'Colors.black': Colors.black,
    'Colors.white': Colors.white,
    'Colors.grey': Colors.grey,
    'Colors.transparent': Colors.transparent,
  };
  static Color? parse(UiValue? v) {
    if (v is IdentifierUiValue) return _colors[v.value];
    if (v is NodeUiValue && v.value.type == 'Color') {
      final argument = v.value.positionalArguments.firstOrNull;
      if (argument is NumberUiValue) return Color(argument.value.toInt());
    }
    return null;
  }
}
