import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/workbench_palette.dart';
import '../../playground/controllers/playground_controller.dart';
import '../../playground/widgets/preview_panel.dart';
import '../controllers/flutter_runner_controller.dart';
import '../models/run_session.dart';
import '../models/runner_preview_target.dart';
import 'runner_preview_host.dart';

class RunnerPreviewPanel extends StatelessWidget {
  const RunnerPreviewPanel({
    super.key,
    required this.playground,
    required this.runner,
  });

  final PlaygroundController playground;
  final FlutterRunnerController runner;

  @override
  Widget build(BuildContext context) {
    final previewUrl = runner.previewUrl;
    final showRealPreview = !runner.isMock &&
        previewUrl != null &&
        runner.status == RunnerStatus.running;
    final target = runner.previewTarget;
    final palette = WorkbenchPalette.of(context);

    return ColoredBox(
      color: palette.background,
      child: Column(
        children: [
          if (!runner.isMock)
            _RunnerStatusBar(
              target: target,
              status: runner.status,
              ready: showRealPreview,
            ),
          Expanded(
            child: showRealPreview
                ? target.opensExternalTab
                    ? const _ExternalWebPreview()
                    : _EmbeddedDevicePreview(
                        url: previewUrl,
                        target: target,
                      )
                : _buildIdlePreview(context),
          ),
        ],
      ),
    );
  }

  Widget _buildIdlePreview(BuildContext context) {
    final inherited = Theme.of(context);
    final palette = WorkbenchPalette.of(context);
    final scheme = inherited.colorScheme.copyWith(
      surface: palette.surface,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceRaised,
      surfaceContainerHighest: palette.surfaceRaised,
      outlineVariant: palette.border,
      onSurface: palette.text,
      onSurfaceVariant: palette.muted,
      primary: palette.accent,
    );

    return Theme(
      data: inherited.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: palette.background,
        dividerColor: palette.border,
        textTheme: inherited.textTheme.apply(
          bodyColor: palette.text,
          displayColor: palette.text,
        ),
        iconTheme: IconThemeData(color: palette.muted),
      ),
      child: PreviewPanel(controller: playground),
    );
  }
}

class _RunnerStatusBar extends StatelessWidget {
  const _RunnerStatusBar({
    required this.target,
    required this.status,
    required this.ready,
  });

  final RunnerPreviewTarget target;
  final RunnerStatus status;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final statusColor = ready ? scheme.primary : palette.muted;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        border: Border(
          bottom: BorderSide(color: palette.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: statusColor.withValues(alpha: .20),
              ),
            ),
            child: Icon(
              ready ? Icons.cloud_done_outlined : Icons.cloud_queue_outlined,
              size: 14,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ready
                  ? context.l10n.tr(
                      '真实 Flutter SDK · ${target.label} · ${status.label}',
                      'Real Flutter SDK · ${target.label} · ${status.label}',
                    )
                  : context.l10n.tr(
                      '真实 Runner · ${target.label} · ${status.label} · 等待 Preview 就绪',
                      'Real Runner · ${target.label} · ${status.label} · Waiting for Preview',
                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbeddedDevicePreview extends StatelessWidget {
  const _EmbeddedDevicePreview({
    required this.url,
    required this.target,
  });

  final String url;
  final RunnerPreviewTarget target;

  @override
  Widget build(BuildContext context) {
    final width = target.viewportWidth!;
    final height = target.viewportHeight!;
    final radius = target == RunnerPreviewTarget.phone ? 28.0 : 20.0;
    final palette = WorkbenchPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: FittedBox(
            key: const ValueKey('real-run-device-fitted-box'),
            fit: BoxFit.contain,
            child: Container(
              key: const ValueKey('real-run-device-viewport'),
              width: width,
              height: height,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: dark ? const Color(0xff050607) : const Color(0xffd8dee8),
                borderRadius: BorderRadius.circular(radius + 6),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor,
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: buildRunnerPreviewHost(url),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExternalWebPreview extends StatelessWidget {
  const _ExternalWebPreview();

  @override
  Widget build(BuildContext context) {
    final palette = WorkbenchPalette.of(context);

    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 23,
                    color: palette.accent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.tr(
                  '网页预览使用独立浏览器标签页',
                  'Web preview opens in a separate browser tab',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                context.l10n.tr(
                  '运行完成后会自动打开。若浏览器阻止新标签页，请允许本站打开弹窗后重新运行。',
                  'It opens automatically after the run completes. If the browser blocks the new tab, allow pop-ups for this site and run again.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.muted,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
