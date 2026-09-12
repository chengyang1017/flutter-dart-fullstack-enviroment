import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/controllers/lesson_controller.dart';
import 'package:flutter_ui_playground/features/lessons/data/author_answer_repository.dart';
import 'package:flutter_ui_playground/features/lessons/data/lesson_progress_store.dart';
import 'package:flutter_ui_playground/features/lessons/widgets/lesson_preview_panel.dart';
import 'package:flutter_ui_playground/features/lessons/widgets/lesson_result_panel.dart';
import 'package:flutter_ui_playground/features/playground/widgets/device_preview_frame.dart';

import 'fixtures/lesson_fixture.dart';

void main() {
  const lesson = testLesson;

  testWidgets('UI 步骤预览只显示设备渲染界面', (tester) async {
    final controller = LessonController(
      lesson: lesson,
      store: LessonProgressStore.memory(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPreviewPanel(
            currentStep: lesson.steps.first,
            playgroundController: controller.playground,
          ),
        ),
      ),
    );
    expect(find.byType(DevicePreviewFrame), findsOneWidget);
    expect(find.byType(LessonResultPanel), findsNothing);
    expect(find.text('继续完善'), findsNothing);
  });

  testWidgets('非 UI 步骤预览只显示不可视化说明', (tester) async {
    final controller = LessonController(
      lesson: lesson,
      store: LessonProgressStore.memory(),
    );
    addTearDown(controller.dispose);
    await controller.goTo(1);
    await controller.check();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonPreviewPanel(
            currentStep: lesson.steps[1],
            playgroundController: controller.playground,
          ),
        ),
      ),
    );
    expect(find.textContaining('没有可视化界面'), findsOneWidget);
    expect(find.textContaining('请在“结果”中查看'), findsOneWidget);
    expect(find.byType(DevicePreviewFrame), findsNothing);
    expect(find.byType(LessonResultPanel), findsNothing);
    expect(find.text('继续完善'), findsNothing);
  });

  testWidgets('不存在的作者答案保持尚未录入', (tester) async {
    final answer = await AuthorAnswerRepository().load(
      'assets/lessons/not-recorded.dart',
    );
    expect(answer.status, AuthorAnswerStatus.notRecorded);
    expect(answer.code, isNull);
  });
}
