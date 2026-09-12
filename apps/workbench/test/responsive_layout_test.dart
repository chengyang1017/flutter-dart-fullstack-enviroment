import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';
import 'package:flutter_ui_playground/features/playground/screens/playground_screen.dart';
import 'package:flutter_ui_playground/features/playground/widgets/device_preview_frame.dart';

Future<void> pumpAtSize(
  WidgetTester tester,
  Size size, {
  Widget child = const MaterialApp(home: PlaygroundScreen()),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('宽度 390 显示代码、预览、文件和控制台标签', (tester) async {
    await pumpAtSize(tester, const Size(390, 844));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('控制台'), findsOneWidget);
  });

  testWidgets('宽度 390 不出现横向 RenderFlex overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousHandler);

    await pumpAtSize(tester, const Size(390, 844));

    expect(
      errors.where(
        (error) => error.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });

  testWidgets('宽度 1000 显示宽屏 Workspace 与代码预览标签', (tester) async {
    await pumpAtSize(tester, const Size(1000, 800));

    final wideLayout = find.byKey(const ValueKey('wide-playground-layout'));
    expect(wideLayout, findsOneWidget);
    expect(
      find.descendant(of: wideLayout, matching: find.byType(Row)),
      findsWidgets,
    );
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('代码'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);
  });

  testWidgets('DevicePreviewFrame 保持 390 / 844 比例', (tester) async {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);
    await pumpAtSize(
      tester,
      const Size(500, 900),
      child: MaterialApp(
        home: Scaffold(
          body: DevicePreviewFrame(
            controller: controller,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final size = tester.getSize(
      find.byKey(const ValueKey('device-preview-logical-size')),
    );
    expect(size.width, 390);
    expect(size.height, 844);
    expect(size.aspectRatio, closeTo(390 / 844, .0001));
  });

  testWidgets('窄屏工具栏可以横向滚动', (tester) async {
    await pumpAtSize(tester, const Size(390, 844));

    final scroll = find.byKey(const ValueKey('playground-toolbar-scroll'));
    expect(scroll, findsOneWidget);
    final widget = tester.widget<SingleChildScrollView>(scroll);
    expect(widget.scrollDirection, Axis.horizontal);

    await tester.drag(scroll, const Offset(-250, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
