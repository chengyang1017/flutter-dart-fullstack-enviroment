import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/playground/widgets/code_flow_panel.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('wire mode stays live and follows the cursor automatically', (
    tester,
  ) async {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);

    controller.textController.selection = const CodeLineSelection(
      baseIndex: 2,
      baseOffset: 4,
      extentIndex: 2,
      extentOffset: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 640,
            child: CodeFlowPanel(controller: controller),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('电线模式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wire-mode-live-indicator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('code-flow-analyze-button')), findsNothing);
    expect(find.byKey(const ValueKey('function-call-graph')), findsOneWidget);
    expect(find.text('main'), findsOneWidget);

    controller.textController.selection = const CodeLineSelection(
      baseIndex: 19,
      baseOffset: 8,
      extentIndex: 19,
      extentOffset: 8,
    );

    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();

    expect(find.byKey(const ValueKey('function-call-graph')), findsOneWidget);
    expect(find.text('PracticeExample.build'), findsOneWidget);
  });
}
