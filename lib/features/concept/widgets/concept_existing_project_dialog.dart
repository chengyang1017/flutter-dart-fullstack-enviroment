import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../workspace/models/workspace_project.dart';

Future<WorkspaceProject?> showConceptExistingProjectDialog(
  BuildContext context, {
  required List<WorkspaceProject> projects,
  String? activeProjectId,
}) {
  return showDialog<WorkspaceProject>(
    context: context,
    builder: (_) => ConceptExistingProjectDialog(
      projects: projects,
      activeProjectId: activeProjectId,
    ),
  );
}

class ConceptExistingProjectDialog extends StatefulWidget {
  const ConceptExistingProjectDialog({
    super.key,
    required this.projects,
    this.activeProjectId,
  });

  final List<WorkspaceProject> projects;
  final String? activeProjectId;

  @override
  State<ConceptExistingProjectDialog> createState() =>
      _ConceptExistingProjectDialogState();
}

class _ConceptExistingProjectDialogState
    extends State<ConceptExistingProjectDialog> {
  late String? selectedProjectId;

  @override
  void initState() {
    super.initState();
    selectedProjectId = widget.projects.any(
      (project) => project.id == widget.activeProjectId,
    )
        ? widget.activeProjectId
        : (widget.projects.isEmpty ? null : widget.projects.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AlertDialog(
      key: const ValueKey('concept-existing-project-dialog'),
      title: Text(l10n.tr('打开现有项目', 'Open existing project')),
      content: SizedBox(
        width: 640,
        child: widget.projects.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  l10n.tr(
                    '项目库里还没有可打开的项目。',
                    'There are no projects available in the project library yet.',
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.tr(
                      '选择项目模式已经创建、导入或从 Git 拉取的 Flutter 项目。打开后概念模式仍然只直接显示 lib/。',
                      'Choose a Flutter project that was created, imported, or pulled from Git in Project Mode. Concept Mode will still expose only lib/ directly.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final project in widget.projects)
                            RadioListTile<String>(
                              key: ValueKey(
                                'concept-existing-project-${project.id}',
                              ),
                              value: project.id,
                              groupValue: selectedProjectId,
                              onChanged: (value) {
                                setState(() => selectedProjectId = value);
                              },
                              secondary: Icon(_iconFor(project)),
                              title: Text(
                                project.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(_subtitle(context, project)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.tr('取消', 'Cancel')),
        ),
        FilledButton.icon(
          key: const ValueKey('concept-existing-project-open'),
          onPressed: selectedProjectId == null ? null : _open,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(l10n.tr('打开', 'Open')),
        ),
      ],
    );
  }

  void _open() {
    final id = selectedProjectId;
    if (id == null) return;
    final project = widget.projects.firstWhere((project) => project.id == id);
    Navigator.of(context).pop(project);
  }

  IconData _iconFor(WorkspaceProject project) {
    if (project.gitRemote != null) return Icons.source_rounded;
    return switch (project.kind) {
      WorkspaceProjectKind.generatedFlutter => Icons.flutter_dash_rounded,
      WorkspaceProjectKind.importedFlutter => Icons.archive_outlined,
      WorkspaceProjectKind.practice => Icons.code_rounded,
    };
  }

  String _subtitle(BuildContext context, WorkspaceProject project) {
    final remote = project.gitRemote;
    if (remote != null) {
      final path = remote.projectPath;
      return path == null
          ? '${remote.repositoryUrl} · ${remote.branch}'
          : '${remote.repositoryUrl} · ${remote.branch} · $path';
    }

    final l10n = context.l10n;
    return switch (project.kind) {
      WorkspaceProjectKind.generatedFlutter =>
        l10n.tr('创建的 Flutter 项目', 'Created Flutter project'),
      WorkspaceProjectKind.importedFlutter =>
        l10n.tr('导入的 Flutter 项目', 'Imported Flutter project'),
      WorkspaceProjectKind.practice =>
        l10n.tr('本地练习项目', 'Local practice project'),
    };
  }
}
