import 'package:flutter/material.dart';
import '../../../../core/utils/edge_insets_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildPadding(BuildContext c, UiNode n, WidgetRenderer r) => Padding(
      padding: EdgeInsetsParser.parse(n.namedArguments['padding']),
      child: child(c, n.namedArguments['child'], r),
    );
