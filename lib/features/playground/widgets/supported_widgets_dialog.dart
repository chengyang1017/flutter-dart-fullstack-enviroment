import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

class SupportedWidgetsDialog extends StatelessWidget {
  const SupportedWidgetsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.tr('支持的组件', 'Supported widgets')),
      content: SingleChildScrollView(
        child: Text(
          l10n.tr(
            'Text · Container · Center · Padding · SizedBox · Row · Column · Card · Icon · ElevatedButton\n\n支持颜色、EdgeInsets、布局枚举、TextStyle，以及嵌套 Widget 与 Widget 列表。',
            'Text · Container · Center · Padding · SizedBox · Row · Column · Card · Icon · ElevatedButton\n\nSupports colors, EdgeInsets, layout enums, TextStyle, nested widgets, and widget lists.',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('知道了', 'Got it')),
        ),
      ],
    );
  }
}
