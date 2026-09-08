import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/playground/widgets/error_panel.dart';
import 'package:flutter_ui_playground/features/runner/controllers/flutter_runner_controller.dart';
import 'package:flutter_ui_playground/features/runner/services/http_flutter_runner_client.dart';
import 'package:flutter_ui_playground/features/runner/services/mock_flutter_runner_client.dart';

void main() {
  testWidgets('real Runner hides Quick Preview parser diagnostics', (tester) async {
    final playground = PlaygroundController();
    playground.error = 'synthetic quick preview parser error';
    final runner = FlutterRunnerController(
      workspace: playground.workspace,
      client: HttpFlutterRunnerClient(baseUrl: 'http://127.0.0.1:8787'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorPanel(controller: playground, maxHeight: 120),
        ),
      ),
    );

    expect(find.text('synthetic quick preview parser error'), findsNothing);
    expect(find.text('快速预览解析错误'), findsNothing);

    runner.dispose();
    playground.dispose();
  });

  testWidgets('Mock Runner keeps Quick Preview parser diagnostics', (tester) async {
    final playground = PlaygroundController();
    playground.error = 'synthetic quick preview parser error';
    final runner = FlutterRunnerController(
      workspace: playground.workspace,
      client: MockFlutterRunnerClient(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorPanel(controller: playground, maxHeight: 120),
        ),
      ),
    );

    expect(find.text('快速预览解析错误'), findsOneWidget);
    expect(find.text('synthetic quick preview parser error'), findsOneWidget);

    runner.dispose();
    playground.dispose();
  });
}
