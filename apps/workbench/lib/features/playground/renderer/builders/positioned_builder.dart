import 'package:flutter/material.dart';

import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildPositioned(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(
      node, {'child', 'left', 'top', 'right', 'bottom', 'width', 'height'});
  return Positioned(
    left: ValueParser.number(node.namedArguments['left']),
    top: ValueParser.number(node.namedArguments['top']),
    right: ValueParser.number(node.namedArguments['right']),
    bottom: ValueParser.number(node.namedArguments['bottom']),
    width: ValueParser.number(node.namedArguments['width']),
    height: ValueParser.number(node.namedArguments['height']),
    child: child(context, node.namedArguments['child'], renderer),
  );
}
