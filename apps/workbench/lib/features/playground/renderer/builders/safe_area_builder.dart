import 'package:flutter/material.dart';

import '../../../../core/utils/edge_insets_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildSafeArea(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(
      node, {'child', 'left', 'top', 'right', 'bottom', 'minimum'});
  return SafeArea(
    left: ValueParser.boolean(node.namedArguments['left']) ?? true,
    top: ValueParser.boolean(node.namedArguments['top']) ?? true,
    right: ValueParser.boolean(node.namedArguments['right']) ?? true,
    bottom: ValueParser.boolean(node.namedArguments['bottom']) ?? true,
    minimum: EdgeInsetsParser.parse(node.namedArguments['minimum']),
    child: child(context, node.namedArguments['child'], renderer),
  );
}
