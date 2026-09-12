import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/core/utils/color_parser.dart';
import 'package:flutter_ui_playground/core/utils/edge_insets_parser.dart';
import 'package:flutter_ui_playground/core/utils/enum_parser.dart';
import 'package:flutter_ui_playground/features/playground/models/ui_value.dart';
import 'package:flutter_ui_playground/features/playground/parser/flutter_ui_parser.dart';

void main() {
  final p = FlutterUiParser();
  test('colors', () {
    expect(
      ColorParser.parse(const IdentifierUiValue('Colors.blue')),
      Colors.blue,
    );
    expect(
      ColorParser.parse(
        p.parse('Container(color: Color(0xFF2196F3))').namedArguments['color'],
      ),
      const Color(0xFF2196F3),
    );
  });
  test('edge insets', () {
    expect(
      EdgeInsetsParser.parse(
        p
            .parse(
              'Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8))',
            )
            .namedArguments['padding'],
      ),
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  });
  test(
    'enums',
    () => expect(
      EnumParser.main(const IdentifierUiValue('MainAxisAlignment.center')),
      MainAxisAlignment.center,
    ),
  );
}
