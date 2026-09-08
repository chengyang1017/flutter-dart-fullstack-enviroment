import 'dart:async';

import 'package:flutter/material.dart';

import '../../assets/widgets/asset_manager_dialog.dart';
import '../../packages/widgets/package_manager_dialog.dart';
import '../../playground/controllers/playground_controller.dart';
import '../../playground/widgets/code_editor_panel.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/models/run_session.dart';
import '../../runner/models/runner_preview_target.dart';
import '../../runner/services/http_flutter_runner_client.dart';
import '../../runner/services/mock_flutter_runner_client.dart';
import '../../runner/services/runner_preview_tab.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/services/hive_workspace_persistence.dart';
import '../../workspace/services/keyed_workspace_snapshot_store.dart';
import '../../workspace/widgets/workspace_editor_tabs.dart';
import '../models/concept_project_context.dart';
import '../widgets/concept_lib_explorer.dart';

class ConceptModeScreen extends StatefulWidget {
  const ConceptModeScreen({
    super.key,
    this.projection,
  });

  /// When supplied, Concept Mode opens a selected Flutter subproject projected
  /// from a larger repository. The projected Workspace itself still has a
  /// normal Flutter root (`lib/`, `assets/`, `pubspec.yaml`), so visual tools do
  /// not need to understand monorepo prefixes.
  final ConceptProjectProjection? projection;

  @override
  State<ConceptModeScreen> createState() => _ConceptModeScreenState();
}

class _ConceptModeScreenState extends State<ConceptModeScreen> {
  static const _runnerApiUrl = String.fromEnvironment('RUNNER_API_URL');
  static const _storageKey = 'concept-mode-workspace';

  late final PlaygroundController controller;
  late final FlutterRunnerController runner;
  RunnerPreviewTabHandle? _pendingWebPreviewTab;

  @override
  void initState() {
    super.initState();

    final persistence = HiveWorkspacePersistence.tryFromOpenBoxes();
    final conceptStore = widget.projection != null || persistence == null
        ? null
        : KeyedWorkspaceSnapshotStore(
            delegate: persistence.snapshotStore,
            storageKey: _storageKey,
          );

    controller = PlaygroundController(
      workspaceStore: conceptStore,
    )..addListener(_refresh);

    final projection = widget.projection;
    if (projection != null) {
      controller.workspace.restoreSnapshot(projection.snapshot);
    }

    runner = FlutterRunnerController(
      workspace: controller.workspace,
      client: _runnerApiUrl.isEmpty
          ? MockFlutterRunnerClient()
          : HttpFlutterRunnerClient(baseUrl: _runnerApiUrl),
    )..addListener(_refresh);
  }

  void _refresh() {
    final pendingTab = _pendingWebPreviewTab;
    if (pendingTab != null) {
      final previewUrl = runner.previewUrl;
      if (runner.canHotReload && previewUrl != null) {
        pendingTab.navigate(previewUrl);
        _pendingWebPreviewTab = null;
      } else if (runner.status == RunnerStatus.error ||
          runner.status == RunnerStatus.stopped) {
        pendingTab.close();
        _pendingWebPreviewTab = null;
      }
    }

    if (mounted) setState(() {});
  }

  void _selectDevice(RunnerPreviewTarget target) {
    runner.selectPreviewTarget(target);
    switch (target) {
      case RunnerPreviewTarget.phone:
        controller.changeDevice(PreviewDevice.androidPhone);
        break;
      case RunnerPreviewTarget.tablet:
        controller.changeDevice(PreviewDevice.tablet);
        break;
      case RunnerPreviewTarget.web:
        controller.changeDevice(PreviewDevice.responsive);
        break;
    }
  }

  Future<void> _runSelectedDevice() async {
    if (!runner.canRun) return;

    final target = runner.previewTarget;
    if (target.opensExternalTab && !runner.isMock) {
      _closePendingWebPreviewTab();
      final tab = openRunnerPreviewTab();
      if (tab.opened) {
        _pendingWebPreviewTab = tab;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '浏览器阻止了网页预览标签页。请允许本站打开弹窗后重新运行。',
            ),
          ),
        );
      }
    } else if (target.opensExternalTab && runner.isMock && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mock Runner 没有真实网页 Preview URL。连接真实 Runner 后可运行网页设备。',
          ),
        ),
      );
    }

    await runner.run();
  }

  void _closePendingWebPreviewTab() {
    _pendingWebPreviewTab?.close();
    _pendingWebPreviewTab = null;
  }

  @override
  void dispose() {
    _closePendingWebPreviewTab();
    runner.removeListener(_refresh);
    runner.dispose();
    controller.removeListener(_refresh);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceLabel = widget.projection?.context.sourceLabel;

    return Scaffold(
      key: const ValueKey('concept-mode-screen'),
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('concept-mode-back'),
          tooltip: '返回主页',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '概念模式',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              sourceLabel == null
                  ? 'Concept Mode · lib/ only'
                  : '$sourceLabel · lib/ only',
              key: sourceLabel == null
                  ? null
                  : const ValueKey('concept-source-project'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.tonalIcon(
              key: const ValueKey('concept-assets-entry'),
              onPressed: () => showAssetManagerDialog(
                context,
                workspace: controller.workspace,
              ),
              icon: const Icon(Icons.perm_media_outlined, size: 17),
              label: const Text('Assets'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.tonalIcon(
              key: const ValueKey('concept-packages-entry'),
              onPressed: () => showPackageManagerDialog(
                context,
                runner: runner,
              ),
              icon: const Icon(Icons.extension_outlined, size: 17),
              label: const Text('依赖'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _ConceptBoundaryBanner(),
          _ConceptRunnerBar(
            runner: runner,
            onDeviceSelected: _selectDevice,
            onRun: () => unawaited(_runSelectedDevice()),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 800) {
                  return _ConceptCompactLayout(
                    controller: controller,
                    runner: runner,
                  );
                }

                return _ConceptWideLayout(
                  controller: controller,
                  runner: runner,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptBoundaryBanner extends StatelessWidget {
  const _ConceptBoundaryBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: scheme.primaryContainer.withValues(alpha: .42),
      child: Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '概念模式只直接控制 lib/。Assets、依赖和运行设备都通过界面管理；pubspec、lock、平台目录继续由系统隐藏处理。',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptRunnerBar extends StatelessWidget {
  const _ConceptRunnerBar({
    required this.runner,
    required this.onDeviceSelected,
    required this.onRun,
  });

  final FlutterRunnerController runner;
  final ValueChanged<RunnerPreviewTarget> onDeviceSelected;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilledButton.icon(
                key: const ValueKey('concept-run-button'),
                onPressed: runner.canRun ? onRun : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(runner.isMock ? 'Run Mock' : 'Run'),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<RunnerPreviewTarget>(
                key: const ValueKey('concept-device-selector'),
                tooltip: '选择运行设备',
                initialValue: runner.previewTarget,
                onSelected: onDeviceSelected,
                itemBuilder: (context) => [
                  _deviceItem(
                    runner,
                    RunnerPreviewTarget.phone,
                    Icons.phone_android,
                  ),
                  _deviceItem(
                    runner,
                    RunnerPreviewTarget.tablet,
                    Icons.tablet_android,
                  ),
                  _deviceItem(
                    runner,
                    RunnerPreviewTarget.web,
                    Icons.language_rounded,
                  ),
                ],
                child: Container(
                  key: const ValueKey('concept-device-selector-surface'),
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(_deviceIcon(runner.previewTarget), size: 18),
                      const SizedBox(width: 7),
                      Text('设备 · ${runner.previewTarget.label}'),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _RunnerStatusPill(runner: runner),
              const SizedBox(width: 12),
              IconButton(
                key: const ValueKey('concept-hot-reload'),
                tooltip: 'Hot Reload',
                onPressed: runner.canHotReload ? runner.hotReload : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                key: const ValueKey('concept-hot-restart'),
                tooltip: 'Hot Restart',
                onPressed: runner.canHotRestart ? runner.hotRestart : null,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
              IconButton(
                key: const ValueKey('concept-stop'),
                tooltip: 'Stop',
                onPressed: runner.canStop ? runner.stop : null,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<RunnerPreviewTarget> _deviceItem(
    FlutterRunnerController runner,
    RunnerPreviewTarget target,
    IconData icon,
  ) {
    return PopupMenuItem<RunnerPreviewTarget>(
      value: target,
      child: Row(
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(target.label),
                Text(
                  target.description,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          if (runner.previewTarget == target)
            const Icon(Icons.check_rounded, size: 18),
        ],
      ),
    );
  }

  IconData _deviceIcon(RunnerPreviewTarget target) {
    return switch (target) {
      RunnerPreviewTarget.phone => Icons.phone_android,
      RunnerPreviewTarget.tablet => Icons.tablet_android,
      RunnerPreviewTarget.web => Icons.language_rounded,
    };
  }
}

class _RunnerStatusPill extends StatelessWidget {
  const _RunnerStatusPill({required this.runner});

  final FlutterRunnerController runner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = runner.status == RunnerStatus.running;

    return Container(
      key: const ValueKey('concept-runner-status'),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer.withValues(alpha: .65)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        '${runner.runnerName} · ${runner.status.label}',
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ConceptWideLayout extends StatelessWidget {
  const _ConceptWideLayout({
    required this.controller,
    required this.runner,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('concept-wide-layout'),
      children: [
        SizedBox(
          width: 240,
          child: ConceptLibExplorer(
            workspace: controller.workspace,
            onOpenFile: controller.selectWorkspaceFile,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _ConceptEditor(controller: controller)),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 360,
          child: _ConceptDeviceArea(
            controller: controller,
            runner: runner,
          ),
        ),
      ],
    );
  }
}

class _ConceptCompactLayout extends StatelessWidget {
  const _ConceptCompactLayout({
    required this.controller,
    required this.runner,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        key: const ValueKey('concept-compact-layout'),
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.code_rounded), text: '代码'),
              Tab(icon: Icon(Icons.phone_android_rounded), text: '设备'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: 190,
                      child: ConceptLibExplorer(
                        workspace: controller.workspace,
                        onOpenFile: controller.selectWorkspaceFile,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _ConceptEditor(controller: controller)),
                  ],
                ),
                _ConceptDeviceArea(
                  controller: controller,
                  runner: runner,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConceptDeviceArea extends StatelessWidget {
  const _ConceptDeviceArea({
    required this.controller,
    required this.runner,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      key: const ValueKey('concept-device-preview'),
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          SizedBox(
            height: 38,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    _iconForTarget(runner.previewTarget),
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Device Preview · ${runner.previewTarget.label}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .45),
          ),
          Expanded(
            child: RunnerPreviewPanel(
              playground: controller,
              runner: runner,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForTarget(RunnerPreviewTarget target) {
    return switch (target) {
      RunnerPreviewTarget.phone => Icons.phone_android_outlined,
      RunnerPreviewTarget.tablet => Icons.tablet_android_outlined,
      RunnerPreviewTarget.web => Icons.language_outlined,
    };
  }
}

class _ConceptEditor extends StatelessWidget {
  const _ConceptEditor({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: scheme.surface,
      child: Column(
        children: [
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.code_rounded, size: 16),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    controller.activeFilePath,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (controller.workspace.isDirty)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          WorkspaceEditorTabs(
            workspace: controller.workspace,
            onSelect: controller.selectWorkspaceFile,
            onClose: controller.closeWorkspaceFile,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: CodeEditorPanel(controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}
