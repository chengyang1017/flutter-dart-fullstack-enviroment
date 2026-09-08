import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ui_playground/features/runner/controllers/flutter_runner_controller.dart';
import 'package:flutter_ui_playground/features/runner/models/run_session.dart';
import 'package:flutter_ui_playground/features/runner/services/mock_flutter_runner_client.dart';
import 'package:flutter_ui_playground/features/workspace/controllers/workspace_controller.dart';

Future<void> settleRunnerEvents() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('mock runner follows run, reload, restart and stop lifecycle', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    final runner = FlutterRunnerController(
      workspace: workspace,
      client: MockFlutterRunnerClient(),
    );
    addTearDown(runner.dispose);
    addTearDown(workspace.dispose);

    expect(runner.status, RunnerStatus.idle);
    expect(runner.canRun, isTrue);
    expect(runner.canHotReload, isFalse);

    await runner.run();
    await settleRunnerEvents();

    expect(runner.session, isNotNull);
    expect(runner.status, RunnerStatus.running);
    expect(runner.canRun, isFalse);
    expect(runner.canHotReload, isTrue);
    expect(
      runner.logs.any((line) => line.contains('flutter run -d web-server')),
      isTrue,
    );

    workspace.updateFileContent(
      'lib/main.dart',
      'void main() { print("reload"); }',
    );

    await runner.hotReload();
    await settleRunnerEvents();

    expect(runner.status, RunnerStatus.running);
    expect(
      runner.logs.any((line) => line.contains('Hot reload requested')),
      isTrue,
    );

    await runner.hotRestart();
    await settleRunnerEvents();

    expect(runner.status, RunnerStatus.running);
    expect(
      runner.logs.any((line) => line.contains('Hot restart requested')),
      isTrue,
    );

    await runner.stop();
    await settleRunnerEvents();

    expect(runner.status, RunnerStatus.stopped);
    expect(runner.canRun, isTrue);
    expect(runner.canHotReload, isFalse);
  });

  test('runner reuses its session after stop', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    final runner = FlutterRunnerController(
      workspace: workspace,
      client: MockFlutterRunnerClient(),
    );
    addTearDown(runner.dispose);
    addTearDown(workspace.dispose);

    await runner.run();
    await settleRunnerEvents();
    final firstSessionId = runner.session!.id;

    await runner.stop();
    await settleRunnerEvents();
    await runner.run();
    await settleRunnerEvents();

    expect(runner.session!.id, firstSessionId);
    expect(runner.status, RunnerStatus.running);
  });

  test('clearConsole removes runner logs without changing status', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    final runner = FlutterRunnerController(
      workspace: workspace,
      client: MockFlutterRunnerClient(),
    );
    addTearDown(runner.dispose);
    addTearDown(workspace.dispose);

    await runner.run();
    await settleRunnerEvents();
    expect(runner.logs, isNotEmpty);

    runner.clearConsole();

    expect(runner.logs, isEmpty);
    expect(runner.status, RunnerStatus.running);
  });

  test('standalone Pub Get verifies only the current pubspec revision', () async {
    final workspace = WorkspaceController.flutterPlayground(
      mainDartContent: 'void main() {}',
    );
    final runner = FlutterRunnerController(
      workspace: workspace,
      client: MockFlutterRunnerClient(),
    );
    addTearDown(runner.dispose);
    addTearDown(workspace.dispose);

    expect(runner.canPubGet, isTrue);
    expect(runner.isPubGetVerifiedForCurrentPubspec, isFalse);

    final result = await runner.pubGet();
    await settleRunnerEvents();

    expect(result.hasPackageConfig, isTrue);
    expect(runner.status, RunnerStatus.ready);
    expect(runner.isPubGetVerifiedForCurrentPubspec, isTrue);
    expect(
      runner.logs.any((line) => line.contains('flutter pub get')),
      isTrue,
    );

    final currentPubspec = workspace.entryAt('pubspec.yaml')!.content;
    workspace.updateFileContent(
      'pubspec.yaml',
      '$currentPubspec\n# package changed\n',
    );

    expect(runner.isPubGetVerifiedForCurrentPubspec, isFalse);
  });
}
