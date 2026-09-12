import 'package:flutter/material.dart';

import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildFlexible(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {'child', 'flex', 'fit'});
  return Flexible(
    flex: ValueParser.integer(node.namedArguments['flex']) ?? 1,
    fit: EnumParser.id(node.namedArguments['fit']) == 'FlexFit.tight'
        ? FlexFit.tight
        : FlexFit.loose,
    child: child(context, node.namedArguments['child'], renderer),
  );
}
