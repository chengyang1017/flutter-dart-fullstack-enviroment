import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../controllers/flutter_runner_controller.dart';
import '../models/run_session.dart';

class RunnerConsolePanel extends StatelessWidget {
  const RunnerConsolePanel({
    super.key,
    required this.runner,
    this.showHeader = true,
    this.logStartIndex = 0,
  });

  final FlutterRunnerController runner;
  final bool showHeader;
  final int logStartIndex;

  @override
  Widget build(BuildContext context) {
    final safeStartIndex = logStartIndex >= 0 && logStartIndex <= runner.logs.length
        ? logStartIndex
        : 0;
    final visibleLogCount = runner.logs.length - safeStartIndex;
    final palette = WorkbenchPalette.of(context);
    final l10n = context.l10n;

    return Material(
      color: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Container(
              height: 36,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                border: Border(
                  top: BorderSide(color: palette.border),
                  bottom: BorderSide(color: palette.border),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    l10n.tr('控制台', 'CONSOLE'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusBadge(status: runner.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      runner.runnerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tr('清空控制台', 'Clear console'),
                    visualDensity: VisualDensity.compact,
                    onPressed: runner.logs.isEmpty ? null : runner.clearConsole,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  ),
                ],
              ),
            ),
          Expanded(
            child: visibleLogCount == 0
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      runner.isMock
                          ? l10n.tr(
                              '当前使用 Mock Runner。启动 flutter-runner-server，并通过 --dart-define=RUNNER_API_URL=... 连接真实 Flutter SDK Runner。',
                              'Mock Runner is active. Start flutter-runner-server and connect a real Flutter SDK Runner with --dart-define=RUNNER_API_URL=....',
                            )
                          : l10n.tr(
                              '真实 Flutter SDK Runner 已连接，运行日志会显示在这里。',
                              'A real Flutter SDK Runner is connected. Runtime logs will appear here.',
                            ),
                      style: TextStyle(
                        fontFamily: 'Cascadia Code',
                        fontFamilyFallback: const [
                          'Cascadia Mono',
                          'Consolas',
                          'monospace',
                        ],
                        fontSize: 12,
                        color: palette.muted,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: visibleLogCount,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: SelectableText(
                        runner.logs[safeStartIndex + index],
                        style: TextStyle(
                          fontFamily: 'Cascadia Code',
                          fontFamilyFallback: const [
                            'Cascadia Mono',
                            'Consolas',
                            'Courier New',
                          ],
                          fontSize: 12,
                          height: 1.4,
                          color: palette.text,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final RunnerStatus status;

  @override
  Widget build(BuildContext context) {
    final isError = status == RunnerStatus.error;
    final isRunning = status == RunnerStatus.running;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isError
            ? scheme.errorContainer
            : isRunning
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isError
              ? scheme.onErrorContainer
              : isRunning
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
