import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

final Set<String> _registeredRunnerPreviewTypes = <String>{};

Widget buildRunnerPreviewHost(String url) {
  final viewType = 'flutter-runner-preview-${url.hashCode}';

  if (_registeredRunnerPreviewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (viewId) => html.IFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('allow', 'clipboard-read; clipboard-write'),
    );
  }

  return HtmlElementView(
    key: ValueKey(url),
    viewType: viewType,
  );
}
