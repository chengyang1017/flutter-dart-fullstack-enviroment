import 'package:flutter/material.dart';
import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../../models/ui_value.dart';
import '../widget_renderer.dart';

Widget buildText(BuildContext c, UiNode n, WidgetRenderer r) {
  r.warnUnknown(n, {'style', 'textAlign'});
  final s = n.namedArguments['style'];
  final style = s is NodeUiValue ? s.value : null;
  return Text(
    ValueParser.string(n.positionalArguments.firstOrNull) ?? '',
    textAlign: EnumParser.textAlign(n.namedArguments['textAlign']),
    style: TextStyle(
      fontSize: ValueParser.number(style?.namedArguments['fontSize']),
      color: ColorParser.parse(style?.namedArguments['color']),
      fontWeight: EnumParser.weight(style?.namedArguments['fontWeight']),
    ),
  );
}
