import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/playground/controllers/playground_controller.dart';

void main() {
  test('default lib/main.dart is a real Flutter entrypoint', () {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);

    final main = controller.workspace.entryAt('lib/main.dart');

    expect(main, isNotNull);
    expect(main!.content, contains("import 'package:flutter/material.dart';"));
    expect(main.content, contains('void main()'));
    expect(main.content, contains('runApp('));
    expect(main.content, contains('// QUICK_PREVIEW_START'));
    expect(main.content, contains('// QUICK_PREVIEW_END'));
  });

  test('Quick Preview extracts the marked widget from real main.dart', () {
    final controller = PlaygroundController();
    addTearDown(controller.dispose);

    controller.runCode();

    expect(controller.error, isNull);
    expect(controller.root, isNotNull);
    expect(controller.root!.type, 'Container');
  });
}
