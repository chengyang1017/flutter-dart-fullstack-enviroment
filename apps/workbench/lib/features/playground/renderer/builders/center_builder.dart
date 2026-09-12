import 'package:flutter/material.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildCenter(BuildContext c, UiNode n, WidgetRenderer r) =>
    Center(child: child(c, n.namedArguments['child'], r));
