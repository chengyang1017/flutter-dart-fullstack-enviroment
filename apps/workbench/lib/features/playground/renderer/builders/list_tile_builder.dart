import 'package:flutter/material.dart';

import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildListTile(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {
    'leading',
    'title',
    'subtitle',
    'trailing',
    'enabled',
    'dense',
    'onTap',
  });
  return ListTile(
    leading: optionalChild(context, node.namedArguments['leading'], renderer),
    title: optionalChild(context, node.namedArguments['title'], renderer),
    subtitle: optionalChild(context, node.namedArguments['subtitle'], renderer),
    trailing: optionalChild(context, node.namedArguments['trailing'], renderer),
    enabled: ValueParser.boolean(node.namedArguments['enabled']) ?? true,
    dense: ValueParser.boolean(node.namedArguments['dense']),
    onTap:
        safeCallback(context, node.namedArguments['onTap'], message: '列表项已点击'),
  );
}
