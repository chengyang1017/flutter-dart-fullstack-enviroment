import 'package:flutter/material.dart';

import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildFloatingActionButton(
  BuildContext context,
  UiNode node,
  WidgetRenderer renderer,
) {
  renderer.warnUnknown(node, {
    'child',
    'tooltip',
    'backgroundColor',
    'foregroundColor',
    'mini',
    'onPressed',
  });
  return FloatingActionButton(
    onPressed: safeCallback(
      context,
      node.namedArguments['onPressed'],
      message: '浮动按钮已点击',
    ),
    tooltip: ValueParser.string(node.namedArguments['tooltip']),
    backgroundColor: ColorParser.parse(node.namedArguments['backgroundColor']),
    foregroundColor: ColorParser.parse(node.namedArguments['foregroundColor']),
    mini: ValueParser.boolean(node.namedArguments['mini']) ?? false,
    child: child(context, node.namedArguments['child'], renderer),
  );
}
