import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../../assets/widgets/asset_manager_dialog.dart';
import '../../concept/widgets/concept_lib_explorer.dart';
import '../../packages/widgets/package_manager_dialog.dart';
import '../../runner/controllers/flutter_runner_controller.dart';
import '../../workspace/widgets/workspace_file_explorer.dart';
import '../controllers/playground_controller.dart';
import '../models/workspace_view_mode.dart';
import 'source_control_panel.dart';

class UnifiedWorkspaceExplorer extends StatelessWidget {
  const UnifiedWorkspaceExplorer({
    super.key,
    required this.controller,
    required this.runner,
    required this.viewMode,
    required this.onViewModeChanged,
    this.onShowDiff,
  });

  final PlaygroundController controller;
  final FlutterRunnerController runner;
  final WorkspaceViewMode viewMode;
  final ValueChanged<WorkspaceViewMode> onViewModeChanged;
  final ValueChanged<String>? onShowDiff;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;
    return Material(
      key: const ValueKey('unified-workspace-explorer'),
      color: palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
            decoration: BoxDecoration(
              color: palette.background,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: palette.surfaceRaised,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ViewModeButton(
                          key: const ValueKey('workspace-view-project'),
                          selected: viewMode == WorkspaceViewMode.project,
                          icon: Icons.account_tree_outlined,
                          label: l10n.tr('项目', 'Project'),
                          onTap: () {
                            onViewModeChanged(WorkspaceViewMode.project);
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: _ViewModeButton(
                          key: const ValueKey('workspace-view-concept'),
                          selected: viewMode == WorkspaceViewMode.concept,
                          icon: Icons.hub_outlined,
                          label: l10n.tr('概念', 'Concept'),
                          onTap: () {
                            onViewModeChanged(WorkspaceViewMode.concept);
                          },
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: _ViewModeButton(
                          key: const ValueKey('workspace-view-source-control'),
                          selected: viewMode == WorkspaceViewMode.sourceControl,
                          icon: Icons.account_tree_rounded,
                          label: 'Git',
                          onTap: () {
                            onViewModeChanged(WorkspaceViewMode.sourceControl);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      viewMode.isSourceControl
                          ? Icons.commit_rounded
                          : viewMode.isConcept
                              ? Icons.filter_alt_outlined
                              : Icons.folder_open_outlined,
                      size: 13,
                      color: palette.muted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        viewMode.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.2,
                          color: palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: viewMode.isSourceControl
                          ? _ExplorerActionButton(
                              key: const ValueKey('source-control-stage-all'),
                              icon: Icons.done_all_rounded,
                              label: 'Stage All',
                              onTap: controller.workspace.stageAll,
                            )
                          : _ExplorerActionButton(
                              key: const ValueKey(
                                'unified-concept-assets-entry',
                              ),
                              icon: Icons.perm_media_outlined,
                              label: 'Assets',
                              onTap: () {
                                showAssetManagerDialog(
                                  context,
                                  workspace: controller.workspace,
                                );
                              },
                            ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: viewMode.isSourceControl
                          ? _ExplorerActionButton(
                              key: const ValueKey('source-control-unstage-all'),
                              icon: Icons.remove_done_rounded,
                              label: 'Unstage',
                              onTap: controller.workspace.unstageAll,
                            )
                          : _ExplorerActionButton(
                              key: const ValueKey(
                                'unified-concept-packages-entry',
                              ),
                              icon: Icons.extension_outlined,
                              label: l10n.tr('依赖', 'Packages'),
                              onTap: () {
                                showPackageManagerDialog(
                                  context,
                                  runner: runner,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: viewMode.isSourceControl
                ? SourceControlPanel(
                    workspace: controller.workspace,
                    onShowDiff: (path) {
                      final callback = onShowDiff;
                      if (callback != null) {
                        callback(path);
                      } else {
                        controller.selectWorkspaceFile(path);
                      }
                    },
                  )
                : viewMode.isConcept
                    ? ConceptLibExplorer(
                        workspace: controller.workspace,
                        onOpenFile: controller.selectWorkspaceFile,
                      )
                    : WorkspaceFileExplorer(
                        workspace: controller.workspace,
                        onOpenFile: controller.selectWorkspaceFile,
                      ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected ? palette.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          hoverColor: palette.surface,
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? palette.accent : palette.muted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? palette.text : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplorerActionButton extends StatelessWidget {
  const _ExplorerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(6),
      child: Ink(
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: palette.surface,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: palette.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
