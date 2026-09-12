import 'package:flutter/material.dart';

import '../../../../core/utils/enum_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildStack(BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {'children', 'alignment', 'fit', 'clipBehavior'});
  return Stack(
    alignment: EnumParser.alignment(node.namedArguments['alignment']),
    fit: switch (EnumParser.id(node.namedArguments['fit'])) {
      'StackFit.expand' => StackFit.expand,
      'StackFit.passthrough' => StackFit.passthrough,
      _ => StackFit.loose,
    },
    clipBehavior: switch (EnumParser.id(node.namedArguments['clipBehavior'])) {
      'Clip.none' => Clip.none,
      'Clip.antiAlias' => Clip.antiAlias,
      'Clip.antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
      _ => Clip.hardEdge,
    },
    children: children(context, node.namedArguments['children'], renderer),
  );
}
