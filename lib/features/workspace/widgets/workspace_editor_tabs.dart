import 'package:flutter/material.dart';

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

        return SizedBox(
          height: 38,
          child: Material(
            color: const Color(0xff181b20),
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
                      color: selected
                          ? const Color(0xff111318)
                          : const Color(0xff181b20),
                      border: const Border(
                        right: BorderSide(color: Color(0xff2c313c)),
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconFor(entry.name),
                          size: 15,
                          color: const Color(0xff9da5b4),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected
                                  ? const Color(0xffe6edf3)
                                  : const Color(0xff9da5b4),
                            ),
                          ),
                        ),
                        if (dirty)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: Color(0xff82aaff),
                            ),
                          ),
                        IconButton(
                          tooltip: '关闭',
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
