import 'package:flutter/material.dart';
import '../../../../core/utils/edge_insets_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildCard(BuildContext c, UiNode n, WidgetRenderer r) => Card(
      margin: EdgeInsetsParser.parse(n.namedArguments['margin']),
      elevation: ValueParser.number(n.namedArguments['elevation']),
      child: child(c, n.namedArguments['child'], r),
    );
