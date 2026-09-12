import 'package:flutter/material.dart';
import '../../features/playground/models/ui_value.dart';

abstract final class EdgeInsetsParser {
  static EdgeInsets parse(UiValue? v) {
    if (v is IdentifierUiValue && v.value == 'EdgeInsets.zero') {
      return EdgeInsets.zero;
    }
    if (v is! NodeUiValue) return EdgeInsets.zero;
    double n(UiValue? x) => x is NumberUiValue ? x.value.toDouble() : 0;
    final a = v.value;
    if (a.type == 'EdgeInsets.all') {
      return EdgeInsets.all(n(a.positionalArguments.firstOrNull));
    }
    if (a.type == 'EdgeInsets.symmetric') {
      return EdgeInsets.symmetric(
        horizontal: n(a.namedArguments['horizontal']),
        vertical: n(a.namedArguments['vertical']),
      );
    }
    if (a.type == 'EdgeInsets.only') {
      return EdgeInsets.only(
        left: n(a.namedArguments['left']),
        top: n(a.namedArguments['top']),
        right: n(a.namedArguments['right']),
        bottom: n(a.namedArguments['bottom']),
      );
    }
    return EdgeInsets.zero;
  }
}
