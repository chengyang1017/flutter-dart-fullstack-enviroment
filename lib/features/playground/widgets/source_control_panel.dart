import 'package:flutter/material.dart';

import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_change.dart';
import '../../workspace/widgets/workspace_file_visuals.dart';

class SourceControlPanel extends StatelessWidget {
  const SourceControlPanel({
    super.key,
    required this.workspace,
    required this.onShowDiff,
  });

  final WorkspaceController workspace;
  final ValueChanged<String> onShowDiff;

  static const _background = Color(0xff111318);
  static const _section = Color(0xff15191f);
  static const _border = Color(0xff272d36);
  static const _text = Color(0xffd7dce5);
  static const _muted = Color(0xff8b93a1);
  static const _accent = Color(0xff82aaff);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) {
        final staged = workspace.stagedChanges;
        final unstaged = workspace.unstagedChanges;

        return ColoredBox(
          color: _background,
          child: Column(
            children: [
              _SourceHeader(
                stagedCount: staged.length,
                unstagedCount: unstaged.length,
              ),
              Expanded(
                child: staged.isEmpty && unstaged.isEmpty
                    ? const _CleanWorkspaceState()
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          _ChangeSection(
                            title: 'STAGED CHANGES',
                            count: staged.length,
                            trailing: staged.isEmpty
                                ? null
                                : _HeaderAction(
                                    tooltip: '全部取消 Stage',
                                    icon: Icons.remove_done_rounded,
                                    onPressed: workspace.unstageAll,
                                  ),
                            children: [
                              for (final change in staged)
                                _ChangeRow(
                                  change: change,
                                  staged: true,
                                  onOpen: () => onShowDiff(change.path),
                                  onStageToggle: () =>
                                      workspace.unstagePath(change.path),
                                ),
                            ],
                          ),
                          _ChangeSection(
                            title: 'CHANGES',
                            count: unstaged.length,
                            trailing: unstaged.isEmpty
                                ? null
                                : _HeaderAction(
                                    tooltip: 'Stage All',
                                    icon: Icons.done_all_rounded,
                                    onPressed: workspace.stageAll,
                                  ),
                            children: [
                              for (final change in unstaged)
                                _ChangeRow(
                                  change: change,
                                  staged: false,
                                  onOpen: () => onShowDiff(change.path),
                                  onStageToggle: () =>
                                      workspace.stagePath(change.path),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.stagedCount,
    required this.unstagedCount,
  });

  final int stagedCount;
  final int unstagedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: const BoxDecoration(
        color: SourceControlPanel._section,
        border: Border(
          bottom: BorderSide(color: SourceControlPanel._border),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 16,
            color: SourceControlPanel._accent,
          ),
          const SizedBox(width: 7),
          const Expanded(
            child: Text(
              'SOURCE CONTROL',
              style: TextStyle(
                color: SourceControlPanel._text,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .45,
              ),
            ),
          ),
          _CountPill(
            value: stagedCount + unstagedCount,
          ),
        ],
      ),
    );
  }
}

class _ChangeSection extends StatelessWidget {
  const _ChangeSection({
    required this.title,
    required this.count,
    required this.children,
    this.trailing,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 5),
          decoration: const BoxDecoration(
            color: Color(0xff13171d),
            border: Border(
              bottom: BorderSide(color: SourceControlPanel._border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: SourceControlPanel._muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .35,
                  ),
                ),
              ),
              _CountPill(value: count),
              if (trailing != null) ...[
                const SizedBox(width: 3),
                trailing!,
              ],
            ],
          ),
        ),
        if (children.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              '无',
              style: TextStyle(
                color: Color(0xff66707f),
                fontSize: 11,
              ),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.change,
    required this.staged,
    required this.onOpen,
    required this.onStageToggle,
  });

  final WorkspaceChange change;
  final bool staged;
  final VoidCallback onOpen;
  final VoidCallback onStageToggle;

  @override
  Widget build(BuildContext context) {
    final fileName = change.path.split('/').last;
    final visual = WorkspaceFileVisual.forName(fileName);
    final status = _status(change.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        hoverColor: const Color(0xff1a2028),
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Row(
              children: [
                Icon(
                  visual.icon,
                  size: 15,
                  color: visual.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SourceControlPanel._text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (change.path.contains('/'))
                        Text(
                          change.path.substring(
                            0,
                            change.path.length - fileName.length - 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff66707f),
                            fontSize: 9.5,
                          ),
                        ),
                    ],
                  ),
                ),
                Tooltip(
                  message: status.label,
                  child: SizedBox(
                    width: 22,
                    child: Text(
                      status.letter,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: staged ? 'Unstage' : 'Stage',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onStageToggle,
                  icon: Icon(
                    staged ? Icons.remove_rounded : Icons.add_rounded,
                    size: 17,
                    color: SourceControlPanel._muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _StatusVisual _status(WorkspaceChangeType type) {
    return switch (type) {
      WorkspaceChangeType.created => const _StatusVisual(
          'A',
          'Added',
          Color(0xff7ec699),
        ),
      WorkspaceChangeType.modified => const _StatusVisual(
          'M',
          'Modified',
          Color(0xffffc777),
        ),
      WorkspaceChangeType.deleted => const _StatusVisual(
          'D',
          'Deleted',
          Color(0xffff757f),
        ),
      WorkspaceChangeType.renamed => const _StatusVisual(
          'R',
          'Renamed',
          Color(0xff82aaff),
        ),
      WorkspaceChangeType.moved => const _StatusVisual(
          'R',
          'Moved',
          Color(0xff82aaff),
        ),
    };
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 15,
        color: SourceControlPanel._muted,
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xff202630),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$value',
        style: const TextStyle(
          color: SourceControlPanel._muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CleanWorkspaceState extends StatelessWidget {
  const _CleanWorkspaceState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 30,
              color: Color(0xff7ec699),
            ),
            SizedBox(height: 10),
            Text(
              'Working tree clean',
              style: TextStyle(
                color: SourceControlPanel._text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '当前 Workspace 没有未提交修改',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SourceControlPanel._muted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusVisual {
  const _StatusVisual(this.letter, this.label, this.color);

  final String letter;
  final String label;
  final Color color;
}
