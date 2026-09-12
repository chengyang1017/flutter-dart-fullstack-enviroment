import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../controller/lesson_controller.dart';

class LessonTaskPanel extends StatelessWidget {
  const LessonTaskPanel({super.key, required this.controller});
  final LessonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = controller.lesson.steps[controller.currentStepIndex];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(step.part, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(step.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(step.instruction),
        const SizedBox(height: 16),
        Text(
          l10n.tr('知识解释', 'Explanation'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(step.explanation),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children:
              step.relatedFiles.map((file) => Chip(label: Text(file))).toList(),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.tr('完成要求', 'Requirements'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...step.requirements.map(
          (requirement) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.radio_button_unchecked, size: 18),
            title: Text(requirement.description),
          ),
        ),
        if (controller.visibleHintCount > 0) ...[
          const Divider(),
          Text(
            l10n.tr('提示', 'Hints'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...step.hints
              .take(controller.visibleHintCount)
              .toList()
              .asMap()
              .entries
              .map(
                (entry) => Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('${entry.key + 1}. ${entry.value}'),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}
