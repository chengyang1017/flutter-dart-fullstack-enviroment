import 'package:flutter/material.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildSizedBox(BuildContext c, UiNode n, WidgetRenderer r) => SizedBox(
      width: ValueParser.number(n.namedArguments['width']),
      height: ValueParser.number(n.namedArguments['height']),
      child: child(c, n.namedArguments['child'], r),
    );
