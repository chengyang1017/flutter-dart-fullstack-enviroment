import 'package:flutter/material.dart';

import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildAppBar(BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {
    'title',
    'leading',
    'actions',
    'centerTitle',
    'backgroundColor',
    'foregroundColor',
    'elevation',
    'automaticallyImplyLeading',
  });
  return AppBar(
    title: optionalChild(context, node.namedArguments['title'], renderer),
    leading: optionalChild(context, node.namedArguments['leading'], renderer),
    actions: children(context, node.namedArguments['actions'], renderer),
    centerTitle: ValueParser.boolean(node.namedArguments['centerTitle']),
    backgroundColor: ColorParser.parse(node.namedArguments['backgroundColor']),
    foregroundColor: ColorParser.parse(node.namedArguments['foregroundColor']),
    elevation: ValueParser.number(node.namedArguments['elevation']),
    automaticallyImplyLeading:
        ValueParser.boolean(node.namedArguments['automaticallyImplyLeading']) ??
            true,
  );
}
