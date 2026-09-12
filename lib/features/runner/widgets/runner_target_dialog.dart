import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../models/runner_preview_target.dart';

class RunnerTargetDialog extends StatelessWidget {
  const RunnerTargetDialog({
    super.key,
    required this.onSelected,
  });

  final ValueChanged<RunnerPreviewTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(context.l10n.tr('选择运行设备', 'Choose run target')),
      children: [
        _TargetOption(
          key: const ValueKey('runner-target-phone'),
          icon: Icons.phone_android,
          target: RunnerPreviewTarget.phone,
          onSelected: onSelected,
        ),
        _TargetOption(
          key: const ValueKey('runner-target-tablet'),
          icon: Icons.tablet_android,
          target: RunnerPreviewTarget.tablet,
          onSelected: onSelected,
        ),
        _TargetOption(
          key: const ValueKey('runner-target-web'),
          icon: Icons.open_in_new,
          target: RunnerPreviewTarget.web,
          onSelected: onSelected,
        ),
      ],
    );
  }
}

class _TargetOption extends StatelessWidget {
  const _TargetOption({
    super.key,
    required this.icon,
    required this.target,
    required this.onSelected,
  });

  final IconData icon;
  final RunnerPreviewTarget target;
  final ValueChanged<RunnerPreviewTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: () {
        onSelected(target);
        Navigator.of(context).pop();
      },
      child: Row(
        children: [
          Icon(icon, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  target.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
