import 'package:flutter/material.dart';

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

  static const _workbench = Color(0xff0d1015);
  static const _surface = Color(0xff111318);
  static const _surfaceRaised = Color(0xff15191f);
  static const _border = Color(0xff272d36);
  static const _text = Color(0xffcbd3df);
  static const _muted = Color(0xff8f98a8);
  static const _accent = Color(0xff82aaff);
  static const _success = Color(0xff76c893);

  @override
  Widget build(BuildContext context) {
    final previewUrl = runner.previewUrl;
    final showRealPreview = !runner.isMock &&
        previewUrl != null &&
        runner.status == RunnerStatus.running;
    final target = runner.previewTarget;

    return ColoredBox(
      color: _workbench,
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
    final darkScheme = inherited.colorScheme.copyWith(
      surface: _surface,
      surfaceContainerLowest: _workbench,
      surfaceContainerLow: _surface,
      surfaceContainer: _surface,
      surfaceContainerHigh: _surfaceRaised,
      surfaceContainerHighest: _surfaceRaised,
      outline: const Color(0xff39414c),
      outlineVariant: _border,
      onSurface: _text,
      onSurfaceVariant: _muted,
      primary: _accent,
    );

    return Theme(
      data: inherited.copyWith(
        colorScheme: darkScheme,
        scaffoldBackgroundColor: _workbench,
        dividerColor: _border,
        textTheme: inherited.textTheme.apply(
          bodyColor: _text,
          displayColor: _text,
        ),
        iconTheme: const IconThemeData(color: _muted),
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
    final statusColor = ready
        ? RunnerPreviewPanel._success
        : RunnerPreviewPanel._muted;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: RunnerPreviewPanel._surfaceRaised,
        border: Border(
          bottom: BorderSide(color: RunnerPreviewPanel._border),
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
                  ? '真实 Flutter SDK · ${target.label} · ${status.label}'
                  : '真实 Runner · ${target.label} · ${status.label} · 等待 Preview 就绪',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: RunnerPreviewPanel._text,
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

    return ColoredBox(
      color: RunnerPreviewPanel._workbench,
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
                color: const Color(0xff050607),
                borderRadius: BorderRadius.circular(radius + 6),
                border: Border.all(
                  color: const Color(0xff303640),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
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
    return const ColoredBox(
      color: RunnerPreviewPanel._workbench,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: RunnerPreviewPanel._surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(
                    Icons.open_in_new_rounded,
                    size: 23,
                    color: RunnerPreviewPanel._accent,
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text(
                '网页预览使用独立浏览器标签页',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: RunnerPreviewPanel._text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 7),
              Text(
                '运行完成后会自动打开。若浏览器阻止新标签页，请允许本站打开弹窗后重新运行。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: RunnerPreviewPanel._muted,
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
