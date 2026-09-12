import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../shared/widgets/empty_state.dart';
import '../controllers/playground_controller.dart';
import '../renderer/widget_renderer.dart';
import 'device_preview_frame.dart';

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key, required this.controller});
  final PlaygroundController controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                key: const ValueKey('device-preview-fitted-box'),
                fit: BoxFit.contain,
                child: DevicePreviewFrame(
                  controller: controller,
                  child: Builder(
                    builder: (innerContext) {
                      if (controller.root == null) {
                        return EmptyState(
                          message: innerContext.l10n.tr(
                            '输入代码并点击运行',
                            'Enter code and click Run',
                          ),
                        );
                      }
                      final renderer = WidgetRenderer(
                        onWarning: controller.addWarning,
                      );
                      final rendered =
                          renderer.render(innerContext, controller.root!);
                      if (controller.root!.type == 'Scaffold') {
                        return rendered;
                      }
                      return SingleChildScrollView(
                        child: Center(
                          child: rendered,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
