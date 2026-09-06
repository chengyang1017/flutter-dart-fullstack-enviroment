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

class WidePlaygroundLayout extends StatefulWidget {
  const WidePlaygroundLayout({
    super.key,
    required this.controller,
    required this.runner,
    required this.toolbar,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final Widget toolbar;

  @override
  State<WidePlaygroundLayout> createState() => _WidePlaygroundLayoutState();
}

class _WidePlaygroundLayoutState extends State<WidePlaygroundLayout> {
  bool _showCodeFlow = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        key: const ValueKey('wide-playground-layout'),
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Flutter Practice Workspace',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('toggle-code-flow-panel'),
                    tooltip: _showCodeFlow ? '关闭调用链面板' : '打开调用链面板',
                    onPressed: () {
                      setState(() => _showCodeFlow = !_showCodeFlow);
                    },
                    icon: Icon(
                      _showCodeFlow
                          ? Icons.account_tree
                          : Icons.account_tree_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 260,
                    child: TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.code), text: '代码'),
                        Tab(icon: Icon(Icons.phone_android), text: '预览'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          widget.toolbar,
          Expanded(
            child: TabBarView(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final explorerWidth = constraints.maxWidth < 980 ? 210.0 : 250.0;
                    final flowWidth = (constraints.maxWidth * .28)
                        .clamp(280.0, 360.0)
                        .toDouble();

                    return Row(
                      children: [
                        SizedBox(
                          width: explorerWidth,
                          child: WorkspaceFileExplorer(
                            workspace: widget.controller.workspace,
                            onOpenFile: widget.controller.selectWorkspaceFile,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Column(
                            children: [
                              WorkspaceEditorTabs(
                                workspace: widget.controller.workspace,
                                onSelect: widget.controller.selectWorkspaceFile,
                                onClose: widget.controller.closeWorkspaceFile,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: CodeEditorPanel(
                                    controller: widget.controller,
                                  ),
                                ),
                              ),
                              ErrorPanel(
                                controller: widget.controller,
                                maxHeight: constraints.maxHeight * 0.14,
                              ),
                              SizedBox(
                                height: constraints.maxHeight < 650 ? 125 : 165,
                                child: RunnerConsolePanel(runner: widget.runner),
                              ),
                            ],
                          ),
                        ),
                        if (_showCodeFlow) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: flowWidth,
                            child: CodeFlowPanel(
                              controller: widget.controller,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                RunnerPreviewPanel(
                  playground: widget.controller,
                  runner: widget.runner,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
