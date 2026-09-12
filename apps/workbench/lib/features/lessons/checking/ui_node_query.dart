import '../../playground/models/ui_node.dart';
import '../../playground/models/ui_value.dart';

extension UiNodeQuery on UiNode {
  Iterable<UiNode> flatten() sync* {
    yield this;
    for (final value in [...positionalArguments, ...namedArguments.values]) {
      if (value is NodeUiValue) yield* value.value.flatten();
      if (value is ListUiValue) {
        for (final item in value.values.whereType<NodeUiValue>()) {
          yield* item.value.flatten();
        }
      }
    }
  }

  bool containsWidget(String name) =>
      flatten().any((node) => node.type == name);
  int countWidget(String name) => findWidgets(name).length;
  List<UiNode> findWidgets(String name) =>
      flatten().where((node) => node.type == name).toList();
  bool hasText(String value) => findWidgets('Text').any(
        (node) =>
            node.positionalArguments.firstOrNull is StringUiValue &&
            (node.positionalArguments.first as StringUiValue).value == value,
      );
  bool hasProperty(String widgetName, String propertyName) => findWidgets(
        widgetName,
      ).any((node) => node.namedArguments.containsKey(propertyName));
  bool hasParentChild(String parentName, String childName) => findWidgets(
        parentName,
      ).any((parent) =>
          _directChildren(parent).any((child) => child.type == childName));
}

Iterable<UiNode> _directChildren(UiNode node) sync* {
  for (final value in [
    ...node.positionalArguments,
    ...node.namedArguments.values
  ]) {
    if (value is NodeUiValue) yield value.value;
    if (value is ListUiValue) {
      yield* value.values.whereType<NodeUiValue>().map((item) => item.value);
    }
  }
}
