import 'package:flutter/material.dart';
import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/edge_insets_parser.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildContainer(BuildContext c, UiNode n, WidgetRenderer r) {
  r.warnUnknown(n, {
    'width',
    'height',
    'color',
    'padding',
    'margin',
    'alignment',
    'child',
  });
  return Container(
    width: ValueParser.number(n.namedArguments['width']),
    height: ValueParser.number(n.namedArguments['height']),
    color: ColorParser.parse(n.namedArguments['color']),
    padding: EdgeInsetsParser.parse(n.namedArguments['padding']),
    margin: EdgeInsetsParser.parse(n.namedArguments['margin']),
    alignment: EnumParser.alignment(n.namedArguments['alignment']),
    child: child(c, n.namedArguments['child'], r),
  );
}
