import 'package:flutter/material.dart';

import '../../runner/controllers/flutter_runner_controller.dart';
import '../../runner/widgets/runner_console_panel.dart';
import '../../runner/widgets/runner_preview_panel.dart';
import '../../workspace/widgets/workspace_editor_tabs.dart';
import '../../workspace/widgets/workspace_file_explorer.dart';
import '../controllers/playground_controller.dart';
import 'code_editor_panel.dart';
import 'code_flow_panel.dart';
import 'error_panel.dart';

class CompactPlaygroundLayout extends StatelessWidget {
  const CompactPlaygroundLayout({
    super.key,
    required this.controller,
    required this.runner,
    required this.toolbar,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final Widget toolbar;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const _TitleBar(),
          toolbar,
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '代码', icon: Icon(Icons.code)),
              Tab(text: '预览', icon: Icon(Icons.phone_android)),
              Tab(text: '文件', icon: Icon(Icons.folder_outlined)),
              Tab(text: '控制台', icon: Icon(Icons.terminal)),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _EditorWithErrors(controller: controller),
                RunnerPreviewPanel(
                  playground: controller,
                  runner: runner,
                ),
                _FilesAndWireMode(controller: controller),
                RunnerConsolePanel(runner: runner),
              ],
            ),
          ),
        ],
      );
}

class _EditorWithErrors extends StatelessWidget {
  const _EditorWithErrors({required this.controller});
  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            WorkspaceEditorTabs(
              workspace: controller.workspace,
              onSelect: controller.selectWorkspaceFile,
              onClose: controller.closeWorkspaceFile,
            ),
            Expanded(child: CodeEditorPanel(controller: controller)),
            ErrorPanel(
              controller: controller,
              maxHeight: constraints.maxHeight * .3,
            ),
          ],
        ),
      );
}

class _FilesAndWireMode extends StatelessWidget {
  const _FilesAndWireMode({required this.controller});

  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(text: '文件', icon: Icon(Icons.folder_outlined)),
                Tab(text: '电线模式', icon: Icon(Icons.account_tree_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                WorkspaceFileExplorer(
                  workspace: controller.workspace,
                  onOpenFile: controller.selectWorkspaceFile,
                ),
                CodeFlowPanel(
                  controller: controller,
                  onNavigate: () {
                    DefaultTabController.of(context).animateTo(0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Flutter Practice Workspace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      );
}
