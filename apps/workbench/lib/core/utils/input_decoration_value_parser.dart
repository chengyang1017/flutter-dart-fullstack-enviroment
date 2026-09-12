import 'package:flutter/material.dart';

import '../../features/playground/models/ui_value.dart';
import 'color_parser.dart';
import 'edge_insets_parser.dart';
import 'value_parser.dart';

abstract final class InputDecorationValueParser {
  static InputDecoration parse(UiValue? value) {
    if (value is! NodeUiValue || value.value.type != 'InputDecoration') {
      return const InputDecoration();
    }
    final arguments = value.value.namedArguments;
    return InputDecoration(
      hintText: ValueParser.string(arguments['hintText']),
      labelText: ValueParser.string(arguments['labelText']),
      helperText: ValueParser.string(arguments['helperText']),
      errorText: ValueParser.string(arguments['errorText']),
      prefixText: ValueParser.string(arguments['prefixText']),
      suffixText: ValueParser.string(arguments['suffixText']),
      filled: ValueParser.boolean(arguments['filled']),
      fillColor: ColorParser.parse(arguments['fillColor']),
      border: _border(arguments['border']),
      enabledBorder: _border(arguments['enabledBorder']),
      focusedBorder: _border(arguments['focusedBorder']),
      contentPadding: arguments.containsKey('contentPadding')
          ? EdgeInsetsParser.parse(arguments['contentPadding'])
          : null,
    );
  }

  static InputBorder? _border(UiValue? value) =>
      value is NodeUiValue && value.value.type == 'OutlineInputBorder'
          ? const OutlineInputBorder()
          : null;
}
