import 'package:flutter/material.dart';
import '../../models/ui_value.dart';
import '../widget_renderer.dart';

Widget child(BuildContext c, UiValue? v, WidgetRenderer r) =>
    v is NodeUiValue ? r.render(c, v.value) : const SizedBox.shrink();
Widget? optionalChild(BuildContext c, UiValue? v, WidgetRenderer r) =>
    v is NodeUiValue ? r.render(c, v.value) : null;
List<Widget> children(BuildContext c, UiValue? v, WidgetRenderer r) =>
    v is ListUiValue
        ? v.values
            .whereType<NodeUiValue>()
            .map((x) => r.render(c, x.value))
            .toList()
        : const [];

VoidCallback? safeCallback(
  BuildContext context,
  UiValue? value, {
  String message = '操作已触发',
}) {
  if (value is NullUiValue) return null;
  return () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(message)),
      );
}
