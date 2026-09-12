import 'package:flutter/material.dart';

import '../../../../core/utils/color_parser.dart';
import '../../../../core/utils/enum_parser.dart';
import '../../../../core/utils/value_parser.dart';
import '../../models/ui_node.dart';
import '../../models/ui_value.dart';
import '../widget_renderer.dart';
import 'builder_utils.dart';

Widget buildScaffold(
    BuildContext context, UiNode node, WidgetRenderer renderer) {
  renderer.warnUnknown(node, {
    'appBar',
    'body',
    'backgroundColor',
    'floatingActionButton',
    'floatingActionButtonLocation',
    'bottomNavigationBar',
    'drawer',
    'resizeToAvoidBottomInset',
  });
  final appBarValue = node.namedArguments['appBar'];
  PreferredSizeWidget? appBar;
  if (appBarValue is NodeUiValue) {
    appBar = renderer.renderPreferred(context, appBarValue.value);
  }
  return Scaffold(
    appBar: appBar,
    body: optionalChild(context, node.namedArguments['body'], renderer),
    backgroundColor: ColorParser.parse(node.namedArguments['backgroundColor']),
    floatingActionButton: optionalChild(
      context,
      node.namedArguments['floatingActionButton'],
      renderer,
    ),
    floatingActionButtonLocation: _floatingLocation(
      EnumParser.id(node.namedArguments['floatingActionButtonLocation']),
    ),
    bottomNavigationBar: optionalChild(
      context,
      node.namedArguments['bottomNavigationBar'],
      renderer,
    ),
    drawer: optionalChild(context, node.namedArguments['drawer'], renderer),
    resizeToAvoidBottomInset:
        ValueParser.boolean(node.namedArguments['resizeToAvoidBottomInset']),
  );
}

FloatingActionButtonLocation? _floatingLocation(String? value) =>
    switch (value) {
      'FloatingActionButtonLocation.centerDocked' =>
        FloatingActionButtonLocation.centerDocked,
      'FloatingActionButtonLocation.centerFloat' =>
        FloatingActionButtonLocation.centerFloat,
      'FloatingActionButtonLocation.endDocked' =>
        FloatingActionButtonLocation.endDocked,
      'FloatingActionButtonLocation.endFloat' =>
        FloatingActionButtonLocation.endFloat,
      'FloatingActionButtonLocation.startDocked' =>
        FloatingActionButtonLocation.startDocked,
      'FloatingActionButtonLocation.startFloat' =>
        FloatingActionButtonLocation.startFloat,
      _ => null,
    };
