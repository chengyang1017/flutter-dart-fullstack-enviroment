import 'package:flutter/material.dart';

import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';

Widget buildDivider(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(
      node, {'height', 'thickness', 'indent', 'endIndent', 'color'});
  return Divider(
    height: ValueParser.number(node.namedArguments['height']),
    thickness: ValueParser.number(node.namedArguments['thickness']),
    indent: ValueParser.number(node.namedArguments['indent']),
    endIndent: ValueParser.number(node.namedArguments['endIndent']),
    color: ColorParser.parse(node.namedArguments['color']),
  );
}
