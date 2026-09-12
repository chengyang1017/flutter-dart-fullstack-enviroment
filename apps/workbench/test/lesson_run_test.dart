import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/controllers/lesson_controller.dart';
import 'package:flutter_ui_playground/features/lessons/data/lesson_progress_store.dart';
import 'package:flutter_ui_playground/features/lessons/screens/lesson_screen.dart';
import 'package:flutter_ui_playground/features/lessons/widgets/lesson_code_panel.dart';
import 'package:flutter_ui_playground/features/playground/models/ui_value.dart';

import 'fixtures/lesson_fixture.dart';

void main() {
  late LessonProgressStore store;
  const lesson = testLesson;

  setUp(() => store = LessonProgressStore.memory());

  testWidgets('UI 步骤显示运行按钮', (tester) async {
    final controller = LessonController(lesson: lesson, store: store);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LessonCodePanel(controller: controller)),
      ),
    );
    expect(find.byKey(const ValueKey('lesson-run-button')), findsOneWidget);
  });

  testWidgets('非 UI 步骤不显示 UI 运行按钮', (tester) async {
    final controller = LessonController(lesson: lesson, store: store);
    addTearDown(controller.dispose);
    await controller.goTo(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LessonCodePanel(controller: controller)),
      ),
    );
    expect(find.byKey(const ValueKey('lesson-run-button')), findsNothing);
  });

  test('运行读取编辑器当前代码且不读取作者答案', () async {
    final controller = LessonController(lesson: lesson, store: store);
    controller.playground.textController.text = "Text('用户当前代码')";
    final succeeded = await controller.runCurrentUi();
    expect(succeeded, isTrue);
    expect(
      (controller.playground.root!.positionalArguments.first as StringUiValue)
          .value,
      '用户当前代码',
    );
    expect(controller.playground.code, "Text('用户当前代码')");
    controller.dispose();
  });

  test('运行不覆盖编辑器代码且不完成步骤', () async {
    final controller = LessonController(lesson: lesson, store: store);
    const current = "Text('保持原样')";
    controller.playground.textController.text = current;
    await controller.runCurrentUi();
    expect(controller.playground.code, current);
    expect(controller.completedSteps, isEmpty);
    controller.dispose();
  });

  Future<TabController> pumpCompact(
    WidgetTester tester, {
    required String code,
  }) async {
    final step = lesson.steps.first;
    await store.save(
      lesson.id,
      {
        'currentStep': 0,
        'completedSteps': <String>[],
        'lastCode': <String, String>{step.id: code},
        'fileCodes': <String, String>{step.currentFile: code},
        'attempts': 0,
        'viewedAnswer': false,
      },
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: LessonScreen(lesson: lesson, store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('代码'));
    await tester.pumpAndSettle();
    final context = tester.element(
      find.byKey(const ValueKey('compact-lesson-layout')),
    );
    return DefaultTabController.of(context);
  }

  testWidgets('运行成功后手机端切换到预览', (tester) async {
    final tabs = await pumpCompact(tester, code: "Text('预览成功')");
    await tester.tap(find.byKey(const ValueKey('lesson-run-button')));
    await tester.pumpAndSettle();
    expect(tabs.index, 2);
  });

  testWidgets('运行失败后手机端切换到结果并显示 Parser 错误', (tester) async {
    final tabs = await pumpCompact(tester, code: "Text('缺少括号'");
    await tester.tap(find.byKey(const ValueKey('lesson-run-button')));
    await tester.pumpAndSettle();
    expect(tabs.index, 3);
    expect(find.text('代码解析失败'), findsOneWidget);
  });

  test('运行和检查使用独立状态', () async {
    final controller = LessonController(lesson: lesson, store: store);
    controller.playground.textController.text = "Text('状态')";
    final running = controller.runCurrentUi();
    expect(controller.isRunning, isTrue);
    expect(controller.isChecking, isFalse);
    await running;
    final checking = controller.check();
    expect(controller.isChecking, isTrue);
    expect(controller.isRunning, isFalse);
    await checking;
    controller.dispose();
  });

  test('上一步和下一步原有索引行为保持不变', () async {
    final controller = LessonController(lesson: lesson, store: store);
    expect(controller.currentStepIndex, 0);
    await controller.goTo(1);
    expect(controller.currentStepIndex, 1);
    await controller.goTo(0);
    expect(controller.currentStepIndex, 0);
    controller.dispose();
  });
}
