import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../../workspace/controllers/workspace_controller.dart';
import '../../workspace/models/workspace_change.dart';
import '../../workspace/widgets/workspace_file_visuals.dart';

class WorkspaceDiffPanel extends StatelessWidget {
  const WorkspaceDiffPanel({
    super.key,
    required this.workspace,
    required this.path,
    required this.onClose,
  });

  final WorkspaceController workspace;
  final String path;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: workspace,
      builder: (context, _) {
        final change = workspace.changeForPath(path);
        if (change == null) {
          return _EmptyDiff(path: path, onClose: onClose);
        }

        final palette = WorkbenchPalette.of(context);
        final before = workspace.baseContentForChange(change);
        final after = workspace.currentContentForChange(change);
        final current = workspace.entryAt(change.path);
        final base = workspace.baseEntryForChange(change);
        final isText = (current?.isText ?? true) && (base?.isText ?? true);
        final rows = isText
            ? _buildDiffRows(before ?? '', after ?? '')
            : const <_DiffRow>[];

        final fileName = change.path.split('/').last;
        final visual = WorkspaceFileVisual.forName(
          fileName,
          binary: !isText,
        );

        return ColoredBox(
          color: palette.surface,
          child: Column(
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.only(left: 12, right: 5),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  border: Border(
                    bottom: BorderSide(color: palette.border),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(visual.icon, size: 16, color: visual.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        change.previousPath == null
                            ? change.path
                            : '${change.previousPath}  →  ${change.path}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StageButton(
                      staged: workspace.isPathStaged(change.path),
                      onPressed: () {
                        if (workspace.isPathStaged(change.path)) {
                          workspace.unstagePath(change.path);
                        } else {
                          workspace.stagePath(change.path);
                        }
                      },
                    ),
                    IconButton(
                      tooltip: context.l10n.tr('关闭 Diff', 'Close Diff'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onClose,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              _DiffLegend(change: change),
              Expanded(
                child: isText
                    ? _UnifiedDiffList(rows: rows)
                    : const _BinaryDiffState(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiffLegend extends StatelessWidget {
  const _DiffLegend({required this.change});

  final WorkspaceChange change;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          Text(
            _label(context, change.type),
            style: TextStyle(
              color: palette.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _LegendDot(
            color: const Color(0xff3f8f5d),
            label: context.l10n.tr('新增', 'Added'),
          ),
          const SizedBox(width: 12),
          _LegendDot(
            color: const Color(0xffd84a57),
            label: context.l10n.tr('删除', 'Deleted'),
          ),
        ],
      ),
    );
  }

  String _label(BuildContext context, WorkspaceChangeType type) {
    return switch (type) {
      WorkspaceChangeType.created => context.l10n.tr('新增', 'ADDED'),
      WorkspaceChangeType.modified => context.l10n.tr('已修改', 'MODIFIED'),
      WorkspaceChangeType.deleted => context.l10n.tr('已删除', 'DELETED'),
      WorkspaceChangeType.renamed => context.l10n.tr('已重命名', 'RENAMED'),
      WorkspaceChangeType.moved => context.l10n.tr('已移动', 'MOVED'),
    };
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: palette.muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _UnifiedDiffList extends StatelessWidget {
  const _UnifiedDiffList({required this.rows});

  final List<_DiffRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          context.l10n.tr('没有文本差异', 'No text differences'),
          style: TextStyle(
            color: WorkbenchPalette.of(context).muted,
            fontSize: 12,
          ),
        ),
      );
    }

    return SelectionArea(
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) => _DiffLine(row: rows[index]),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.row});

  final _DiffRow row;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = WorkbenchPalette.of(context);
    final background = switch (row.kind) {
      _DiffKind.added => dark ? const Color(0xff173323) : const Color(0xffe7f6ec),
      _DiffKind.deleted => dark ? const Color(0xff3a1f25) : const Color(0xffffe8eb),
      _DiffKind.same => Colors.transparent,
    };
    final markerColor = switch (row.kind) {
      _DiffKind.added => const Color(0xff3f8f5d),
      _DiffKind.deleted => const Color(0xffd84a57),
      _DiffKind.same => palette.lineNumber,
    };
    final marker = switch (row.kind) {
      _DiffKind.added => '+',
      _DiffKind.deleted => '−',
      _DiffKind.same => ' ',
    };

    return ColoredBox(
      color: background,
      child: SizedBox(
        height: 22,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 46,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: palette.border),
                ),
              ),
              child: Text(
                row.oldLine == null ? '' : '${row.oldLine}',
                style: TextStyle(
                  color: palette.lineNumber,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Container(
              width: 46,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: palette.border),
                ),
              ),
              child: Text(
                row.newLine == null ? '' : '${row.newLine}',
                style: TextStyle(
                  color: palette.lineNumber,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Center(
                child: Text(
                  marker,
                  style: TextStyle(
                    color: markerColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    row.text.isEmpty ? ' ' : row.text,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 12,
                      height: 1.25,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageButton extends StatelessWidget {
  const _StageButton({required this.staged, required this.onPressed});

  final bool staged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: staged ? const Color(0xffc98600) : palette.accent,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: onPressed,
      icon: Icon(
        staged ? Icons.remove_rounded : Icons.add_rounded,
        size: 15,
      ),
      label: Text(
        staged
            ? context.l10n.tr('取消 Stage', 'Unstage')
            : context.l10n.tr('Stage', 'Stage'),
        style: const TextStyle(fontSize: 10.5),
      ),
    );
  }
}

class _EmptyDiff extends StatelessWidget {
  const _EmptyDiff({required this.path, required this.onClose});

  final String path;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return ColoredBox(
      color: palette.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xff3f8f5d),
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr(
                '$path 已没有未提交差异',
                '$path has no uncommitted differences',
              ),
              style: TextStyle(
                color: palette.text,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onClose,
              child: Text(context.l10n.tr('返回编辑器', 'Back to editor')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BinaryDiffState extends StatelessWidget {
  const _BinaryDiffState();

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_outlined,
            size: 32,
            color: palette.muted,
          ),
          const SizedBox(height: 9),
          Text(
            context.l10n.tr(
              '二进制文件暂不显示文本 Diff',
              'Text Diff is not available for binary files',
            ),
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiffKind { same, added, deleted }

class _DiffRow {
  const _DiffRow({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final _DiffKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;
}

List<_DiffRow> _buildDiffRows(String before, String after) {
  final oldLines = before.split('\n');
  final newLines = after.split('\n');

  if (oldLines.length * newLines.length > 360000) {
    return _buildLargeFileDiff(oldLines, newLines);
  }

  final rows = oldLines.length + 1;
  final cols = newLines.length + 1;
  final lcs = List.generate(rows, (_) => List<int>.filled(cols, 0));

  for (var i = oldLines.length - 1; i >= 0; i--) {
    for (var j = newLines.length - 1; j >= 0; j--) {
      lcs[i][j] = oldLines[i] == newLines[j]
          ? lcs[i + 1][j + 1] + 1
          : math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }

  final result = <_DiffRow>[];
  var i = 0;
  var j = 0;
  var oldLine = 1;
  var newLine = 1;

  while (i < oldLines.length && j < newLines.length) {
    if (oldLines[i] == newLines[j]) {
      result.add(
        _DiffRow(
          kind: _DiffKind.same,
          text: oldLines[i],
          oldLine: oldLine++,
          newLine: newLine++,
        ),
      );
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      result.add(
        _DiffRow(
          kind: _DiffKind.deleted,
          text: oldLines[i++],
          oldLine: oldLine++,
        ),
      );
    } else {
      result.add(
        _DiffRow(
          kind: _DiffKind.added,
          text: newLines[j++],
          newLine: newLine++,
        ),
      );
    }
  }

  while (i < oldLines.length) {
    result.add(
      _DiffRow(
        kind: _DiffKind.deleted,
        text: oldLines[i++],
        oldLine: oldLine++,
      ),
    );
  }
  while (j < newLines.length) {
    result.add(
      _DiffRow(
        kind: _DiffKind.added,
        text: newLines[j++],
        newLine: newLine++,
      ),
    );
  }

  return result;
}

List<_DiffRow> _buildLargeFileDiff(
  List<String> oldLines,
  List<String> newLines,
) {
  var prefix = 0;
  while (prefix < oldLines.length &&
      prefix < newLines.length &&
      oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }

  var oldSuffix = oldLines.length - 1;
  var newSuffix = newLines.length - 1;
  while (oldSuffix >= prefix &&
      newSuffix >= prefix &&
      oldLines[oldSuffix] == newLines[newSuffix]) {
    oldSuffix--;
    newSuffix--;
  }

  final result = <_DiffRow>[];
  for (var i = 0; i < prefix; i++) {
    result.add(
      _DiffRow(
        kind: _DiffKind.same,
        text: oldLines[i],
        oldLine: i + 1,
        newLine: i + 1,
      ),
    );
  }
  for (var i = prefix; i <= oldSuffix; i++) {
    result.add(
      _DiffRow(
        kind: _DiffKind.deleted,
        text: oldLines[i],
        oldLine: i + 1,
      ),
    );
  }
  for (var j = prefix; j <= newSuffix; j++) {
    result.add(
      _DiffRow(
        kind: _DiffKind.added,
        text: newLines[j],
        newLine: j + 1,
      ),
    );
  }

  final suffixCount = oldLines.length - oldSuffix - 1;
  for (var k = 0; k < suffixCount; k++) {
    final oldIndex = oldSuffix + 1 + k;
    final newIndex = newSuffix + 1 + k;
    result.add(
      _DiffRow(
        kind: _DiffKind.same,
        text: oldLines[oldIndex],
        oldLine: oldIndex + 1,
        newLine: newIndex + 1,
      ),
    );
  }
  return result;
}
