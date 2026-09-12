import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/export/widgets/export_project_guide_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required String projectType,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => ExportProjectGuideDialog(
                fileName: 'practice.flutterpractice',
                projectType: projectType,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Flutter export clearly explains the practice package', (
    tester,
  ) async {
    await _openDialog(tester, projectType: 'flutter');

    expect(find.text('导出项目'), findsOneWidget);
    expect(
      find.text('你将下载一个练习包，不是完整 Flutter 项目。'),
      findsOneWidget,
    );
    expect(find.text('practice.flutterpractice'), findsOneWidget);
    expect(find.text('Flutter SDK（必需）'), findsOneWidget);
    expect(find.textContaining('Flutter SDK 已经包含 Dart SDK'), findsOneWidget);
    expect(find.textContaining('Dart Frog CLI'), findsNothing);
    expect(find.textContaining('Serverpod CLI'), findsNothing);
    expect(find.text('下载练习包'), findsOneWidget);
  });

  testWidgets('Dart Frog export names its backend requirement', (tester) async {
    await _openDialog(tester, projectType: 'flutter-dart-frog');

    expect(find.text('Flutter + Dart Frog 项目'), findsOneWidget);
    expect(find.text('Flutter SDK（必需）'), findsOneWidget);
    expect(find.text('Dart Frog CLI（此项目需要）'), findsOneWidget);
    expect(
      find.textContaining('练习包保存后端源码，但不会携带 Dart Frog 开发工具'),
      findsOneWidget,
    );
    expect(find.textContaining('Serverpod CLI'), findsNothing);
  });

  testWidgets('Serverpod export explains CLI and optional database tooling', (
    tester,
  ) async {
    await _openDialog(tester, projectType: 'flutter-serverpod-mini');

    expect(find.text('Flutter + Serverpod 项目'), findsOneWidget);
    expect(find.text('Flutter SDK（必需）'), findsOneWidget);
    expect(find.text('Serverpod CLI（此项目需要）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('serverpod-database-note')),
      findsOneWidget,
    );
    expect(find.textContaining('PostgreSQL'), findsOneWidget);
    expect(find.textContaining('Docker'), findsOneWidget);
  });

  testWidgets('beginner notice does not assume command line knowledge', (
    tester,
  ) async {
    await _openDialog(tester, projectType: 'flutter');

    expect(find.byKey(const ValueKey('cli-beginner-note')), findsOneWidget);
    expect(
      find.textContaining('当前版本的本地项目创建器仍是命令行工具'),
      findsOneWidget,
    );
    expect(find.textContaining('你不需要理解 flutter create'), findsOneWidget);
    expect(
      find.textContaining('不会修改或覆盖你电脑里的现有项目'),
      findsOneWidget,
    );
  });
}
