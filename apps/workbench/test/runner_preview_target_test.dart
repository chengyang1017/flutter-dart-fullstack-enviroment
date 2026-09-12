import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/models/runner_preview_target.dart';
import 'package:flutter_ui_playground/features/runner/widgets/runner_target_dialog.dart';

void main() {
  test('real run targets define phone and tablet viewports', () {
    expect(RunnerPreviewTarget.phone.viewportWidth, 390);
    expect(RunnerPreviewTarget.phone.viewportHeight, 844);
    expect(RunnerPreviewTarget.tablet.viewportWidth, 820);
    expect(RunnerPreviewTarget.tablet.viewportHeight, 1180);
    expect(RunnerPreviewTarget.web.viewportWidth, isNull);
    expect(RunnerPreviewTarget.web.viewportHeight, isNull);
    expect(RunnerPreviewTarget.web.opensExternalTab, isTrue);
  });

  testWidgets('run target dialog offers phone tablet and web', (tester) async {
    RunnerPreviewTarget? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => RunnerTargetDialog(
                    onSelected: (target) => selected = target,
                  ),
                );
              },
              child: const Text('Run'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(find.text('选择运行设备'), findsOneWidget);
    expect(find.byKey(const ValueKey('runner-target-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('runner-target-tablet')), findsOneWidget);
    expect(find.byKey(const ValueKey('runner-target-web')), findsOneWidget);
    expect(find.text('手机'), findsOneWidget);
    expect(find.text('平板'), findsOneWidget);
    expect(find.text('网页'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('runner-target-tablet')));
    await tester.pumpAndSettle();

    expect(selected, RunnerPreviewTarget.tablet);
    expect(find.text('选择运行设备'), findsNothing);
  });
}
