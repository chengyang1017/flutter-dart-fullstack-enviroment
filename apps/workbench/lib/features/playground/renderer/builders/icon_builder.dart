import 'package:flutter/material.dart';
import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../../models/ui_value.dart';
import '../widget_renderer.dart';

Widget buildIcon(BuildContext c, UiNode n, WidgetRenderer r) {
  const icons = {
    'Icons.home': Icons.home,
    'Icons.person': Icons.person,
    'Icons.settings': Icons.settings,
    'Icons.favorite': Icons.favorite,
    'Icons.language': Icons.language,
    'Icons.code': Icons.code,
    'Icons.star': Icons.star,
  };
  final v = n.positionalArguments.firstOrNull;
  return Icon(
    icons[v is IdentifierUiValue ? v.value : ''] ?? Icons.help_outline,
    size: ValueParser.number(n.namedArguments['size']),
    color: ColorParser.parse(n.namedArguments['color']),
  );
}
