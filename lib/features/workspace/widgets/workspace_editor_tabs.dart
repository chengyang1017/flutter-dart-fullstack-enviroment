import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../controllers/workspace_controller.dart';

class WorkspaceEditorTabs extends StatelessWidget {
  const WorkspaceEditorTabs({
    super.key,
    required this.workspace,
    required this.onSelect,
    required this.onClose,
    this.pathFilter,
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final bool Function(String path)? pathFilter;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) {
        final openFiles = pathFilter == null
            ? workspace.openFiles
            : workspace.openFiles.where(pathFilter!).toList(growable: false);
        final palette = WorkbenchPalette.of(context);

        return SizedBox(
          height: 38,
          child: Material(
            color: palette.surfaceRaised,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: openFiles.length,
              itemBuilder: (context, index) {
                final path = openFiles[index];
                final entry = workspace.entryAt(path);
                if (entry == null) return const SizedBox.shrink();

                final selected = path == workspace.activePath;
                final dirty = workspace.isFileDirty(path);

                return InkWell(
                  onTap: () => onSelect(path),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 110,
                      maxWidth: 220,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? palette.surface : palette.surfaceRaised,
                      border: Border(
                        right: BorderSide(color: palette.border),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconFor(entry.name),
                          size: 15,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? palette.text : palette.muted,
                            ),
                          ),
                        ),
                        if (dirty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: palette.accent,
                            ),
                          ),
                        IconButton(
                          tooltip: context.l10n.tr('关闭', 'Close'),
                          visualDensity: VisualDensity.compact,
                          iconSize: 14,
                          onPressed: () => onClose(path),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String name) {
    if (name.endsWith('.dart')) return Icons.code;
    if (name.endsWith('.yaml') || name.endsWith('.yml')) return Icons.tune;
    if (name.endsWith('.json')) return Icons.data_object;
    return Icons.description_outlined;
  }
}
