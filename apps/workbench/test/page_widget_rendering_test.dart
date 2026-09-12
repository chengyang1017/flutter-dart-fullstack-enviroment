import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/lessons/controllers/lesson_controller.dart';
import 'package:flutter_ui_playground/features/lessons/data/lesson_progress_store.dart';
import 'package:flutter_ui_playground/features/lessons/widgets/lesson_preview_panel.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/playground/parser/flutter_ui_parser.dart';
import 'package:flutter_ui_playground/features/playground/renderer/widget_renderer.dart';
import 'package:flutter_ui_playground/features/playground/widgets/preview_panel.dart';

import 'fixtures/lesson_fixture.dart';

const publishPageCode = '''
Scaffold(
  backgroundColor: Colors.white,
  appBar: AppBar(
    title: Text('发布帖子'),
    centerTitle: true,
  ),
  body: SafeArea(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            minLines: 6,
            maxLines: null,
            maxLength: 1000,
            decoration: InputDecoration(
              hintText: '分享你的想法……',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: null,
            child: Text('发布'),
          ),
        ],
      ),
    ),
  ),
)
''';

Future<List<String>> pumpRendered(WidgetTester tester, String code) async {
  final warnings = <String>[];
  final node = FlutterUiParser().parse(code);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => WidgetRenderer(
          onWarning: warnings.add,
        ).render(context, node),
      ),
    ),
  );
  await tester.pump();
  return warnings;
}

void main() {
  testWidgets('Scaffold 可以作为根节点渲染', (tester) async {
    await pumpRendered(tester, "Scaffold(body: Text('页面正文'))");
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('Scaffold appBar 构建真正 AppBar 并显示 title', (tester) async {
    await pumpRendered(
      tester,
      "Scaffold(appBar: AppBar(title: Text('标题')), body: Text('正文'))",
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('标题'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.appBar, isA<PreferredSizeWidget>());
  });

  testWidgets('Scaffold body 与 SafeArea 可以显示', (tester) async {
    await pumpRendered(
      tester,
      "Scaffold(body: SafeArea(child: Text('安全正文'))) ",
    );
    expect(find.byType(SafeArea), findsOneWidget);
    expect(find.text('安全正文'), findsOneWidget);
  });

  testWidgets('Expanded 放在 Column 中可以渲染', (tester) async {
    await pumpRendered(
      tester,
      "Scaffold(body: Column(children: [Expanded(flex: 2, child: Text('扩展'))]))",
    );
    expect(find.byType(Expanded), findsOneWidget);
    expect(find.text('扩展'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListView children 可以滚动显示', (tester) async {
    final items = List.generate(12, (index) => "Text('项目 $index')").join(',');
    await pumpRendered(
      tester,
      'Scaffold(body: ListView(padding: EdgeInsets.all(8), children: [$items]))',
    );
    expect(find.byType(ListView), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.text('项目 11'), findsOneWidget);
  });

  testWidgets('Stack 与 Positioned 可以渲染', (tester) async {
    await pumpRendered(
      tester,
      "Scaffold(body: Stack(children: [Text('底层'), Positioned(left: 10, top: 20, child: Text('定位'))]))",
    );
    expect(find.byType(Stack), findsWidgets);
    expect(find.byType(Positioned), findsWidgets);
    expect(find.text('定位'), findsOneWidget);
  });

  testWidgets('用户 Scaffold 外部不会嵌套第二个 Scaffold', (tester) async {
    final controller = PlaygroundController();
    controller.root = FlutterUiParser().parse(
      "Scaffold(appBar: AppBar(title: Text('唯一')), body: Text('正文'))",
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PreviewPanel(controller: controller)),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('未支持属性只产生警告', (tester) async {
    final warnings = await pumpRendered(
      tester,
      "Scaffold(extendBody: true, body: Text('仍然显示'))",
    );
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('仍然显示'), findsOneWidget);
    expect(warnings.single, contains('extendBody'));
  });

  test('发布帖子完整页面代码可以解析', () {
    final node = FlutterUiParser().parse(publishPageCode);
    expect(node.type, 'Scaffold');
    expect(node.namedArguments, contains('appBar'));
    expect(node.namedArguments, contains('body'));
  });

  testWidgets('发布帖子完整页面代码可以渲染', (tester) async {
    await pumpRendered(tester, publishPageCode);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('发布帖子'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自由练习原有 Widget 保持正常', (tester) async {
    await pumpRendered(
      tester,
      "Center(child: Container(color: Colors.blue, child: Text('原有组件'))) ",
    );
    expect(find.byType(Center), findsOneWidget);
    expect(find.byType(Container), findsOneWidget);
    expect(find.text('原有组件'), findsOneWidget);
  });

  testWidgets('教材 UI 预览复用同一 Renderer', (tester) async {
    final controller = LessonController(
      lesson: testLesson,
      store: LessonProgressStore.memory(),
    );
    controller.playground.root = FlutterUiParser().parse(
      "Scaffold(appBar: AppBar(title: Text('教材页面')), body: Text('内容'))",
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: LessonPreviewPanel(
          currentStep: controller.lesson.steps.first,
          playgroundController: controller.playground,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('教材页面'), findsOneWidget);
  });
}
