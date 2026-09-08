import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/home/screens/home_screen.dart';

void main() {
  testWidgets(
    'home exposes concept mode with lib only, assets, devices and runner controls',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(home: HomeScreen()),
      );

      final conceptEntry = find.byKey(
        const ValueKey('home-concept-mode-entry'),
      );
      final projectEntry = find.byKey(
        const ValueKey('home-project-mode-entry'),
      );
      final lessonEntry = find.byKey(
        const ValueKey('home-lesson-mode-entry'),
      );

      expect(conceptEntry, findsOneWidget);
      expect(projectEntry, findsOneWidget);
      expect(lessonEntry, findsOneWidget);
      expect(find.text('自由练习'), findsNothing);
      expect(find.text('项目模式'), findsOneWidget);
      expect(
        tester.getTopLeft(conceptEntry).dy,
        lessThan(tester.getTopLeft(projectEntry).dy),
      );

      await tester.tap(conceptEntry);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('concept-mode-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-lib-explorer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-assets-entry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-packages-entry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-run-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-device-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-device-preview')),
        findsOneWidget,
      );
      expect(find.text('设备 · 手机'), findsOneWidget);
      expect(find.text('Device Preview · 手机'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('concept-lib-entry-lib/main.dart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('concept-lib-entry-pubspec.yaml')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('concept-lib-entry-analysis_options.yaml')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('concept-device-selector-surface')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('平板').last);
      await tester.pumpAndSettle();

      expect(find.text('设备 · 平板'), findsOneWidget);
      expect(find.text('Device Preview · 平板'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('concept-run-button')));
      await tester.pumpAndSettle();

      expect(find.text('Mock Flutter Runner · Running'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('concept-assets-entry')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('资源界面化 · 系统自动维护 assets/ 与 pubspec.yaml'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('asset-upload-files')),
        findsOneWidget,
      );
      expect(find.text('pubspec 已声明 assets/'), findsOneWidget);
    },
  );
}
