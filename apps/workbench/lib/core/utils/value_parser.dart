import '../../features/playground/models/ui_value.dart';

abstract final class ValueParser {
  static double? number(UiValue? v) =>
      v is NumberUiValue ? v.value.toDouble() : null;
  static String? string(UiValue? v) => v is StringUiValue ? v.value : null;
  static bool? boolean(UiValue? v) => v is BooleanUiValue ? v.value : null;
  static int? integer(UiValue? v) =>
      v is NumberUiValue ? v.value.toInt() : null;
}
