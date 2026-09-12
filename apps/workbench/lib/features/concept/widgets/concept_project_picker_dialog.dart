import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../workspace/models/workspace_snapshot.dart';
import '../models/concept_project_context.dart';
import '../services/concept_project_projection_service.dart';

Future<ConceptProjectProjection?> showConceptProjectPickerDialog(
  BuildContext context, {
  required WorkspaceSnapshot repositorySnapshot,
  required String repositoryName,
}) {
  return showDialog<ConceptProjectProjection>(
    context: context,
    builder: (_) => ConceptProjectPickerDialog(
      repositorySnapshot: repositorySnapshot,
      repositoryName: repositoryName,
    ),
  );
}

class ConceptProjectPickerDialog extends StatefulWidget {
  const ConceptProjectPickerDialog({
    super.key,
    required this.repositorySnapshot,
    required this.repositoryName,
  });

  final WorkspaceSnapshot repositorySnapshot;
  final String repositoryName;

  @override
  State<ConceptProjectPickerDialog> createState() =>
      _ConceptProjectPickerDialogState();
}

class _ConceptProjectPickerDialogState
    extends State<ConceptProjectPickerDialog> {
  static const _service = ConceptProjectProjectionService();

  late final List<ConceptFlutterProjectCandidate> candidates;
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    candidates = _service.detectFlutterProjects(widget.repositorySnapshot);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AlertDialog(
      key: const ValueKey('concept-project-picker'),
      title: Text(l10n.tr('选择 Flutter 项目', 'Choose Flutter project')),
      content: SizedBox(
        width: 620,
        child: candidates.isEmpty
            ? const _NoFlutterProject()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.repositoryName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    candidates.length == 1
                        ? l10n.tr(
                            '检测到 1 个可运行 Flutter App。进入后显示应用，并自动寻找同仓库后端。',
                            'Found 1 runnable Flutter app. It will open directly, and the backend will be detected from the same repository automatically.',
                          )
                        : l10n.tr(
                            '检测到 ${candidates.length} 个可运行 Flutter App。选择主应用；后端会从同仓库自动识别。',
                            'Found ${candidates.length} runnable Flutter apps. Choose the main app; the backend will be detected from the same repository automatically.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var index = 0;
                              index < candidates.length;
                              index++)
                            _ProjectCandidateTile(
                              key: ValueKey(
                                'concept-project-candidate-${candidates[index].projectRoot}',
                              ),
                              index: index,
                              candidate: candidates[index],
                              selectedIndex: selectedIndex,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => selectedIndex = value);
                                }
                              },
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
          key: const ValueKey('concept-project-open'),
          onPressed: candidates.isEmpty ? null : _openSelected,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l10n.tr('打开概念模式', 'Open Concept Mode')),
        ),
      ],
    );
  }

  void _openSelected() {
    final projection = _service.project(
      repositorySnapshot: widget.repositorySnapshot,
      repositoryName: widget.repositoryName,
      candidate: candidates[selectedIndex],
    );
    Navigator.of(context).pop(projection);
  }
}

class _ProjectCandidateTile extends StatelessWidget {
  const _ProjectCandidateTile({
    super.key,
    required this.index,
    required this.candidate,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int index;
  final ConceptFlutterProjectCandidate candidate;
  final int selectedIndex;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<int>(
      value: index,
      groupValue: selectedIndex,
      onChanged: onChanged,
      title: Text(
        candidate.projectName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        candidate.displayPath,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      secondary: const Icon(Icons.flutter_dash_rounded),
    );
  }
}

class _NoFlutterProject extends StatelessWidget {
  const _NoFlutterProject();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.tr(
                '这个仓库里没有检测到同时包含 pubspec.yaml、Flutter SDK 依赖和 lib/main.dart 的可运行 Flutter App。',
                'No runnable Flutter app was found with pubspec.yaml, a Flutter SDK dependency, and lib/main.dart.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
