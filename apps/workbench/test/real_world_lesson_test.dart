import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/checking/lesson_checker.dart';
import 'package:flutter_ui_playground/features/lessons/controllers/lesson_controller.dart';
import 'package:flutter_ui_playground/features/lessons/data/lesson_progress_store.dart';
import 'package:flutter_ui_playground/features/lessons/models/lesson_requirement.dart';
import 'package:flutter_ui_playground/features/lessons/models/lesson_step.dart';
import 'package:hive/hive.dart';

import 'fixtures/lesson_fixture.dart';

LessonStep dartStep(List<LessonRequirement> requirements) => LessonStep(
      id: 'dart-test',
      part: 'Part test',
      title: 'dart',
      instruction: 'dart',
      stepType: LessonStepType.logic,
      explanation: 'dart',
      starterCode: '',
      hints: const ['hint'],
      requirements: requirements,
      relatedFiles: const ['create_post_page.dart'],
      checkMode: CheckMode.dartAst,
    );

void main() {
  const lesson = testLesson;
  final checker = LessonChecker();

  test('UI 步骤使用 uiAst 检查', () {
    final uiSteps =
        lesson.steps.where((step) => step.stepType == LessonStepType.ui);
    expect(uiSteps, isNotEmpty);
    expect(uiSteps.every((step) => step.checkMode == CheckMode.uiAst), isTrue);
  });

  test('逻辑步骤识别 trim 和空值判断', () {
    final step = LessonStep(
      id: 'logic-test',
      part: 'Part test',
      title: 'logic',
      instruction: 'logic',
      stepType: LessonStepType.logic,
      explanation: 'logic',
      starterCode: '',
      hints: const ['hint'],
      requirements: const [RequiredTrimRequirement(), RequiredIfRequirement()],
      relatedFiles: const ['create_post_page.dart'],
      checkMode: CheckMode.dartAst,
    );
    final result = checker.checkStep(
      "final message = input.text.trim(); if (message.isEmpty) return;",
      step,
    );
    expect(result.passed, isTrue);
  });

  test('Service 步骤识别 createPost 方法', () {
    final step = dartStep(const [RequiredMethodRequirement('createPost')]);
    expect(
      checker
          .checkStep(
            'class PostService { Future<void> createPost(String value) async {} }',
            step,
          )
          .passed,
      isTrue,
    );
  });

  test('Firebase 步骤识别 posts 集合及指定字段', () {
    final step = dartStep(const [
      RequiredCollectionRequirement('posts'),
      RequiredMapFieldsRequirement(['authorId', 'content', 'createdAt']),
    ]);
    final code = """
Future<void> save(dynamic account, String body) async {
  await FirebaseFirestore.instance.collection('posts').add({
    'content': body,
    'createdAt': FieldValue.serverTimestamp(),
    'authorId': account.uid,
  });
}
""";
    expect(checker.checkStep(code, step).passed, isTrue);
  });

  test('不同变量名的正确实现仍可通过', () {
    final step = dartStep(const [RequiredTrimRequirement()]);
    expect(
      checker.checkStep("final cleanedBody = editor.text.trim();", step).passed,
      isTrue,
    );
  });

  test('缺少 authorId 时不能通过', () {
    final step = dartStep(const [
      RequiredCollectionRequirement('posts'),
      RequiredMapFieldsRequirement(['authorId', 'content', 'createdAt']),
    ]);
    final code = """
await FirebaseFirestore.instance.collection('posts').add({
  'content': body,
  'createdAt': FieldValue.serverTimestamp(),
});
""";
    expect(checker.checkStep(code, step).passed, isFalse);
  });

  group('多文件进度', () {
    late Directory directory;
    late Box<dynamic> box;
    late LessonProgressStore store;

    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('multi-file-lesson');
      Hive.init(directory.path);
      box = await Hive.openBox<dynamic>('multi_file_progress');
      store = LessonProgressStore(box);
    });
    tearDown(() => box.clear());
    tearDownAll(() async {
      await box.close();
      await directory.delete(recursive: true);
    });

    test('多文件代码能够分别保存恢复', () async {
      final first = LessonController(lesson: lesson, store: store);
      first.playground.textController.text = 'class CreatePostPage {}';
      await first.switchFile('post_service.dart');
      first.playground.textController.text = 'class PostService {}';
      await first.switchFile('create_post_page.dart');
      await first.check();
      first.dispose();

      final restored = LessonController(lesson: lesson, store: store);
      expect(
        restored.fileCodes['create_post_page.dart'],
        'class CreatePostPage {}',
      );
      expect(restored.fileCodes['post_service.dart'], 'class PostService {}');
      restored.dispose();
    });

    test('课程完成进度可以恢复', () async {
      final first = LessonController(lesson: lesson, store: store);
      first.playground.textController.text =
          "Column(children: [TextField(), ElevatedButton(onPressed: null, child: Text('发布'))])";
      await first.check();
      first.dispose();
      final restored = LessonController(lesson: lesson, store: store);
      expect(restored.completedSteps, contains(lesson.steps.first.id));
      restored.dispose();
    });
  });
}
