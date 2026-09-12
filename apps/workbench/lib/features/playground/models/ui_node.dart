import 'ui_value.dart';

class UiNode {
  const UiNode({
    required this.type,
    this.positionalArguments = const [],
    this.namedArguments = const {},
  });
  final String type;
  final List<UiValue> positionalArguments;
  final Map<String, UiValue> namedArguments;
}
