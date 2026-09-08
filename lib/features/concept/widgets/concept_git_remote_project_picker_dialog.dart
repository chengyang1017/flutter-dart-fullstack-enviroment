import 'package:flutter/material.dart';

import '../../workspace/models/workspace_git_pull.dart';

Future<WorkspaceGitFlutterProjectCandidate?>
    showConceptGitRemoteProjectPickerDialog(
  BuildContext context, {
  required String repositoryUrl,
  required List<WorkspaceGitFlutterProjectCandidate> candidates,
}) {
  return showDialog<WorkspaceGitFlutterProjectCandidate>(
    context: context,
    builder: (_) => ConceptGitRemoteProjectPickerDialog(
      repositoryUrl: repositoryUrl,
      candidates: candidates,
    ),
  );
}

class ConceptGitRemoteProjectPickerDialog extends StatefulWidget {
  const ConceptGitRemoteProjectPickerDialog({
    super.key,
    required this.repositoryUrl,
    required this.candidates,
  });

  final String repositoryUrl;
  final List<WorkspaceGitFlutterProjectCandidate> candidates;

  @override
  State<ConceptGitRemoteProjectPickerDialog> createState() =>
      _ConceptGitRemoteProjectPickerDialogState();
}

class _ConceptGitRemoteProjectPickerDialogState
    extends State<ConceptGitRemoteProjectPickerDialog> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      key: const ValueKey('concept-git-project-picker'),
      title: const Text('选择 Flutter App'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _displayRepository(widget.repositoryUrl),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '检测到 ${widget.candidates.length} 个可运行 Flutter App。选择后系统会记住这个路径，之后 Pull / Push 不需要再次选择。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0;
                        index < widget.candidates.length;
                        index++)
                      RadioListTile<int>(
                        key: ValueKey(
                          'concept-git-project-candidate-${widget.candidates[index].projectPath ?? 'root'}',
                        ),
                        value: index,
                        groupValue: selectedIndex,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedIndex = value);
                          }
                        },
                        title: Text(
                          widget.candidates[index].projectName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          widget.candidates[index].displayPath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: const Icon(Icons.flutter_dash_rounded),
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
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('concept-git-project-select'),
          onPressed: widget.candidates.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    widget.candidates[selectedIndex],
                  ),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('打开这个 App'),
        ),
      ],
    );
  }

  String _displayRepository(String source) {
    final scp = RegExp(r'^[^@]+@[^:]+:(.+)$').firstMatch(source);
    var path = scp?.group(1);
    if (path == null) {
      final uri = Uri.tryParse(source);
      if (uri != null && uri.host.isNotEmpty) path = uri.path;
    }
    if (path == null) return source;

    final segments = path
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 2) return source;
    return '${segments[segments.length - 2]}/${segments.last.replaceFirst(RegExp(r'\.git$'), '')}';
  }
}
