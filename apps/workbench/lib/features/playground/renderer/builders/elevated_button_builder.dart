import 'package:flutter/material.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildElevatedButton(BuildContext c, UiNode n, WidgetRenderer r) =>
    ElevatedButton(
      onPressed: safeCallback(
        c,
        n.namedArguments['onPressed'],
        message: '按钮已点击',
      ),
      child: child(c, n.namedArguments['child'], r),
    );
