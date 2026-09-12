import 'dart:html' as html;

class RunnerPreviewTabHandle {
  RunnerPreviewTabHandle(this._window);

  final html.WindowBase? _window;

  bool get opened => _window != null;

  void navigate(String url) {
    _window?.location.href = url;
  }

  void close() {
    _window?.close();
  }
}

RunnerPreviewTabHandle openRunnerPreviewTab() {
  return RunnerPreviewTabHandle(
    html.window.open('about:blank', '_blank'),
  );
}
