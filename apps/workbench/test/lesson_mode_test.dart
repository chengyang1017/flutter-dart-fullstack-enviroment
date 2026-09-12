import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/controllers/lesson_controller.dart';
import 'package:flutter_ui_playground/features/lessons/data/lesson_progress_store.dart';
import 'package:flutter_ui_playground/features/lessons/screens/lesson_screen.dart';
import 'package:hive/hive.dart';

import 'fixtures/lesson_fixture.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late LessonProgressStore store;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('lesson-progress-test');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('lesson_progress_test');
    store = LessonProgressStore(box);
  });

  tearDown(() async => box.clear());
  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  Future<void> pumpLesson(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LessonScreen(
          lesson: testLesson,
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('手机宽度显示教材 TabBar', (tester) async {
    await pumpLesson(tester, const Size(390, 844));
    expect(find.byKey(const ValueKey('compact-lesson-layout')), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    for (final label in ['任务', '代码', '预览', '结果']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('宽屏显示双栏', (tester) async {
    await pumpLesson(tester, const Size(1000, 800));
    final wide = find.byKey(const ValueKey('wide-lesson-layout'));
    expect(wide, findsOneWidget);
    expect(find.descendant(of: wide, matching: find.byType(Row)), findsWidgets);
    expect(
      find.descendant(of: wide, matching: find.byType(TabBar)),
      findsOneWidget,
    );
  });

  test('进度可以保存和恢复', () async {
    final first = LessonController(lesson: testLesson, store: store);
    first.playground.textController.text =
        "Column(children: [TextField(), ElevatedButton(onPressed: null, child: Text('发布'))])";
    await first.check();
    await first.goTo(1);
    first.playground.textController.text = "Text('最后代码')";
    await first.check();
    first.dispose();

    final restored = LessonController(lesson: testLesson, store: store);
    expect(restored.currentStepIndex, 1);
    expect(restored.attempts, 2);
    expect(restored.lastCode[testLesson.steps[1].id], "Text('最后代码')");
    expect(restored.completedSteps, contains(testLesson.steps.first.id));
    restored.dispose();
  });
}
