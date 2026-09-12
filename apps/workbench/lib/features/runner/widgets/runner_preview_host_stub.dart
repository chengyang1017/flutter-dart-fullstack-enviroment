import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

Widget buildRunnerPreviewHost(String url) {
  final english = AppLocaleController.locale.value.languageCode == 'en';
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: SelectableText(
        english
            ? 'Real Flutter Preview is running:\n$url\n\nThis platform cannot embed a Web iframe. Open this address in your browser.'
            : '真实 Flutter Preview 已启动：\n$url\n\n当前平台不能内嵌 Web iframe，请在浏览器打开这个地址。',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
