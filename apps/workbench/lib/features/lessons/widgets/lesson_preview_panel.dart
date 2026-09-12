import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../playground/controllers/playground_controller.dart';
import '../../playground/widgets/preview_panel.dart';
import '../models/lesson_step.dart';

class LessonPreviewPanel extends StatelessWidget {
  const LessonPreviewPanel({
    super.key,
    required this.currentStep,
    required this.playgroundController,
  });

  final LessonStep currentStep;
  final PlaygroundController playgroundController;

  @override
  Widget build(BuildContext context) {
    if (currentStep.stepType == LessonStepType.ui) {
      return PreviewPanel(controller: playgroundController);
    }

    final l10n = context.l10n;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.all(24),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_tree_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  l10n.tr(
                    '当前步骤是逻辑或数据层代码，没有可视化界面。\n请在“结果”中查看代码检查结果。',
                    'This step contains logic or data-layer code, so there is no visual UI preview.\nOpen “Result” to view the code checks.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const Text(
                  '_publishPost()\n→ PostService.createPost()\n→ Firebase',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'monospace', height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
