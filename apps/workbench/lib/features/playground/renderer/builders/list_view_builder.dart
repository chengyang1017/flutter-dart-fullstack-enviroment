import 'package:flutter/material.dart';

import '../../../../core/utils/edge_insets_parser.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildListView(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node,
      {'children', 'padding', 'scrollDirection', 'reverse', 'shrinkWrap'});
  return ListView(
    padding: node.namedArguments.containsKey('padding')
        ? EdgeInsetsParser.parse(node.namedArguments['padding'])
        : null,
    scrollDirection: EnumParser.id(node.namedArguments['scrollDirection']) ==
            'Axis.horizontal'
        ? Axis.horizontal
        : Axis.vertical,
    reverse: ValueParser.boolean(node.namedArguments['reverse']) ?? false,
    shrinkWrap: ValueParser.boolean(node.namedArguments['shrinkWrap']) ?? false,
    children: children(context, node.namedArguments['children'], renderer),
  );
}
