import 'package:flutter/material.dart';

import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildExpanded(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {'child', 'flex'});
  return Expanded(
    flex: ValueParser.integer(node.namedArguments['flex']) ?? 1,
    child: child(context, node.namedArguments['child'], renderer),
  );
}
