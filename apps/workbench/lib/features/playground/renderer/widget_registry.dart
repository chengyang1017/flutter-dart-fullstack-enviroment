import 'package:flutter/material.dart';
import '../models/ui_node.dart';
import 'widget_renderer.dart';

typedef WidgetNodeBuilder = Widget Function(
    BuildContext, UiNode, WidgetRenderer);

class WidgetRegistry {
  WidgetRegistry(this.builders);
  final Map<String, WidgetNodeBuilder> builders;
  WidgetNodeBuilder? operator [](String type) => builders[type];
  void register(String type, WidgetNodeBuilder builder) {
    builders[type] = builder;
  }
}
