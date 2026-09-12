import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/parser/flutter_ui_parser.dart';
import 'package:flutter_ui_playground/features/playground/renderer/widget_renderer.dart';

Future<List<String>> pumpCode(WidgetTester tester, String code) async {
  final warnings = <String>[];
  final node = FlutterUiParser().parse(code);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => WidgetRenderer(
            onWarning: warnings.add,
          ).render(context, node),
        ),
      ),
    ),
  );
  await tester.pump();
  return warnings;
}

void main() {
  testWidgets('可以渲染基础 TextField', (tester) async {
    await pumpCode(tester, 'TextField()');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('可以读取 hintText', (tester) async {
    await pumpCode(
      tester,
      "TextField(decoration: InputDecoration(hintText: '请输入内容'))",
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, '请输入内容');
  });

  testWidgets('可以读取 maxLength', (tester) async {
    await pumpCode(tester, 'TextField(maxLength: 120)');
    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 120);
  });

  testWidgets('可以读取 minLines 与 maxLines', (tester) async {
    await pumpCode(tester, 'TextField(minLines: 2, maxLines: 5)');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 2);
    expect(field.maxLines, 5);
  });

  testWidgets('maxLines null 可以解析为多行', (tester) async {
    await pumpCode(tester, 'TextField(minLines: 2, maxLines: null)');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 2);
    expect(field.maxLines, isNull);
  });

  testWidgets('controller 参数使用安全预览 Controller', (tester) async {
    await pumpCode(tester, 'TextField(controller: postController)');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller, isA<TextEditingController>());
    expect(find.textContaining('渲染失败'), findsNothing);
  });

  testWidgets('不支持的 TextField 属性只产生警告', (tester) async {
    final warnings = await pumpCode(tester, 'TextField(cursorWidth: 3)');
    expect(find.byType(TextField), findsOneWidget);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('cursorWidth'));
  });

  testWidgets('非法 minLines maxLines 不导致崩溃', (tester) async {
    final warnings = await pumpCode(
      tester,
      'TextField(minLines: 5, maxLines: 2)',
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 2);
    expect(field.maxLines, 2);
    expect(warnings.single, contains('minLines'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('解析 InputDecoration 的完整常用属性', (tester) async {
    await pumpCode(
      tester,
      """TextField(
  textAlign: TextAlign.end,
  keyboardType: TextInputType.emailAddress,
  decoration: InputDecoration(
    labelText: '邮箱',
    helperText: '用于登录',
    prefixText: '@',
    suffixText: '.com',
    filled: true,
    fillColor: Colors.grey,
    border: OutlineInputBorder(),
    enabledBorder: OutlineInputBorder(),
    focusedBorder: OutlineInputBorder(),
    contentPadding: EdgeInsets.all(16),
  ),
)""",
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.textAlign, TextAlign.end);
    expect(field.keyboardType, TextInputType.emailAddress);
    expect(field.decoration?.labelText, '邮箱');
    expect(field.decoration?.filled, isTrue);
    expect(field.decoration?.border, isA<OutlineInputBorder>());
    expect(field.decoration?.contentPadding, const EdgeInsets.all(16));
  });
}
