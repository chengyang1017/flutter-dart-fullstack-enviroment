import 'ui_node.dart';

sealed class UiValue {
  const UiValue();
}

class StringUiValue extends UiValue {
  const StringUiValue(this.value);
  final String value;
}

class NumberUiValue extends UiValue {
  const NumberUiValue(this.value);
  final num value;
}

class BooleanUiValue extends UiValue {
  const BooleanUiValue(this.value);
  final bool value;
}

class NullUiValue extends UiValue {
  const NullUiValue();
}

class IdentifierUiValue extends UiValue {
  const IdentifierUiValue(this.value);
  final String value;
}

class NodeUiValue extends UiValue {
  const NodeUiValue(this.value);
  final UiNode value;
}

class ListUiValue extends UiValue {
  const ListUiValue(this.values);
  final List<UiValue> values;
}
