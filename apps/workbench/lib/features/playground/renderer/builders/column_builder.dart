import 'package:flutter/material.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildColumn(BuildContext c, UiNode n, WidgetRenderer r) => Column(
      mainAxisAlignment: EnumParser.main(n.namedArguments['mainAxisAlignment']),
      crossAxisAlignment:
          EnumParser.cross(n.namedArguments['crossAxisAlignment']),
      mainAxisSize: EnumParser.size(n.namedArguments['mainAxisSize']),
      children: children(c, n.namedArguments['children'], r),
    );
