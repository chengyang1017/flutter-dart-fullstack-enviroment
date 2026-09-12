import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controller/lesson_controller.dart';
import '../models/lesson_step.dart';

class LessonResultPanel extends StatelessWidget {
  const LessonResultPanel({super.key, required this.controller});
  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = controller.checkResult;

    if (controller.playground.error != null &&
        controller.lesson.steps[controller.currentStepIndex].stepType ==
            LessonStepType.ui) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.tr('代码解析失败', 'Code parsing failed'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(controller.playground.error!),
        ],
      );
    }

    if (result == null) {
      return Center(
        child: Text(
          l10n.tr(
            '点击“检查”查看每项要求的结果。',
            'Click “Check” to see the result for each requirement.',
          ),
        ),
      );
    }

    if (result.parseError != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.tr('代码解析失败', 'Code parsing failed'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(result.parseError!),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          result.passed
              ? l10n.tr('本步骤完成', 'Step complete')
              : l10n.tr('继续完善', 'Keep improving'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        ...result.results.map(
          (item) => ListTile(
            leading: Icon(
              item.passed ? Icons.check_circle : Icons.cancel,
              color: item.passed ? Colors.green : Colors.red,
            ),
            title: Text(item.requirement.description),
          ),
        ),
      ],
    );
  }
}
