import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controller/lesson_controller.dart';

class LessonActionBar extends StatelessWidget {
  const LessonActionBar({
    super.key,
    required this.controller,
    required this.onAnswer,
  });
  final LessonController controller;
  final VoidCallback onAnswer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: controller.currentStepIndex > 0
                      ? () => controller.goTo(controller.currentStepIndex - 1)
                      : null,
                  child: Text(l10n.tr('上一步', 'Previous')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: controller.showNextHint,
                  icon: const Icon(Icons.lightbulb_outline),
                  label: Text(l10n.tr('提示', 'Hint')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: controller.isChecking ? null : controller.check,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    controller.isChecking
                        ? l10n.tr('检查中…', 'Checking…')
                        : l10n.tr('检查', 'Check'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onAnswer,
                  child: Text(l10n.tr('标准答案', 'Reference answer')),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: controller.currentStepIndex <
                          controller.lesson.steps.length - 1
                      ? () => controller.goTo(controller.currentStepIndex + 1)
                      : null,
                  child: Text(l10n.tr('下一步', 'Next')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
