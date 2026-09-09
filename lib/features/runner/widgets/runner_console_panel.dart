import 'package:flutter/material.dart';

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

    return Material(
      color: const Color(0xff111318),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Container(
              height: 36,
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: const BoxDecoration(
                color: Color(0xff15181e),
                border: Border(
                  top: BorderSide(color: Color(0xff262a32)),
                  bottom: BorderSide(color: Color(0xff262a32)),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    'CONSOLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                      color: Color(0xffaeb4bf),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff7f8795),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '清空控制台',
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
                          ? '当前使用 Mock Runner。启动 flutter-runner-server，并通过 --dart-define=RUNNER_API_URL=... 连接真实 Flutter SDK Runner。'
                          : '真实 Flutter SDK Runner 已连接，运行日志会显示在这里。',
                      style: const TextStyle(
                        fontFamily: 'Cascadia Code',
                        fontFamilyFallback: [
                          'Cascadia Mono',
                          'Consolas',
                          'monospace',
                        ],
                        fontSize: 12,
                        color: Color(0xff7f8795),
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
                        style: const TextStyle(
                          fontFamily: 'Cascadia Code',
                          fontFamilyFallback: [
                            'Cascadia Mono',
                            'Consolas',
                            'Courier New',
                          ],
                          fontSize: 12,
                          height: 1.4,
                          color: Color(0xffc7ccd6),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: isError
            ? const Color(0xff3d2024)
            : isRunning
                ? const Color(0xff173524)
                : const Color(0xff252a33),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isError
              ? const Color(0xffff9b9b)
              : isRunning
                  ? const Color(0xff8de5ad)
                  : const Color(0xffb8c0cc),
        ),
      ),
    );
  }
}
