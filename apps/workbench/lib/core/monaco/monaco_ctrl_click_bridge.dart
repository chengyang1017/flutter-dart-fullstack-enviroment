import 'package:flutter_monaco/flutter_monaco.dart';

typedef MonacoCtrlClickCallback = Future<void> Function(
  Position position,
);

class MonacoCtrlClickBridge {
  static const MonacoAction _action =
      MonacoAction('workbench.ctrlClick');

  static Future<MonacoActionRegistration> install({
    required MonacoController controller,
    required MonacoCtrlClickCallback onCtrlClick,
  }) async {
    final registration = await controller.addAction(
      const MonacoActionDescriptor(
        id: _action,
        label: 'Go to definition',
        precondition: 'editorTextFocus',
      ),
      () async {
        final position = await controller.getCursorPosition();

        if (position == null) {
          return;
        }

        await onCtrlClick(position);
      },
    );

    await controller.runJavaScript(r'''
(() => {
  const editor = monaco.editor.getEditors()[0];

  if (!editor) {
    return;
  }

  window.__workbenchCtrlClick?.dispose?.();

  const disposable = editor.onMouseDown((event) => {
    const mouse = event.event;
    const position = event.target?.position;

    if (!mouse || !position) {
      return;
    }

    const modifierPressed =
      mouse.ctrlKey === true ||
      mouse.metaKey === true;

    const primaryButton =
      mouse.leftButton === true;

    if (!modifierPressed || !primaryButton) {
      return;
    }

    mouse.preventDefault?.();
    mouse.stopPropagation?.();

    editor.setPosition(position);
    editor.focus();

    editor.trigger(
      'mouse',
      'workbench.ctrlClick',
      null,
    );
  });

  window.__workbenchCtrlClick = {
    dispose() {
      disposable.dispose();
      delete window.__workbenchCtrlClick;
    },
  };
})();
''');

    return registration;
  }

  static Future<void> uninstall({
    required MonacoController controller,
    required MonacoActionRegistration registration,
  }) async {
    try {
      await controller.runJavaScript(
        'window.__workbenchCtrlClick?.dispose?.();',
      );
    } catch (_) {
      // Editor/WebView may already be tearing down.
    }

    await registration.dispose();
  }
}