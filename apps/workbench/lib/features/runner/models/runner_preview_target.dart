import '../../../core/l10n/app_localizations.dart';

enum RunnerPreviewTarget {
  phone,
  tablet,
  web,
}

enum RunnerPreviewOrientation {
  portrait,
  landscape,
}

String _localized(String zh, String en) =>
    AppLocaleController.locale.value.languageCode == 'en' ? en : zh;

extension RunnerPreviewOrientationInfo on RunnerPreviewOrientation {
  String get label => switch (this) {
        RunnerPreviewOrientation.portrait => _localized('竖屏', 'Portrait'),
        RunnerPreviewOrientation.landscape => _localized('横屏', 'Landscape'),
      };
}

extension RunnerPreviewTargetInfo on RunnerPreviewTarget {
  String get label => switch (this) {
        RunnerPreviewTarget.phone => _localized('手机', 'Phone'),
        RunnerPreviewTarget.tablet => _localized('平板', 'Tablet'),
        RunnerPreviewTarget.web => _localized('网页', 'Web'),
      };

  String get description => switch (this) {
        RunnerPreviewTarget.phone => _localized(
            '在 IDE 内以 390 × 844 的手机视口运行',
            'Run inside the IDE with a 390 × 844 phone viewport',
          ),
        RunnerPreviewTarget.tablet => _localized(
            '在 IDE 内以 820 × 1180 的平板视口运行',
            'Run inside the IDE with an 820 × 1180 tablet viewport',
          ),
        RunnerPreviewTarget.web => _localized(
            '运行完成后在新的浏览器标签页打开',
            'Open in a new browser tab after the run starts',
          ),
      };

  bool get opensExternalTab => this == RunnerPreviewTarget.web;
  bool get supportsOrientation => !opensExternalTab;

  double? get viewportWidth => switch (this) {
        RunnerPreviewTarget.phone => 390,
        RunnerPreviewTarget.tablet => 820,
        RunnerPreviewTarget.web => null,
      };

  double? get viewportHeight => switch (this) {
        RunnerPreviewTarget.phone => 844,
        RunnerPreviewTarget.tablet => 1180,
        RunnerPreviewTarget.web => null,
      };

  double? viewportWidthFor(RunnerPreviewOrientation orientation) {
    final width = viewportWidth;
    final height = viewportHeight;
    if (width == null || height == null) return null;
    return orientation == RunnerPreviewOrientation.portrait ? width : height;
  }

  double? viewportHeightFor(RunnerPreviewOrientation orientation) {
    final width = viewportWidth;
    final height = viewportHeight;
    if (width == null || height == null) return null;
    return orientation == RunnerPreviewOrientation.portrait ? height : width;
  }

  String? viewportDimensionsFor(RunnerPreviewOrientation orientation) {
    final width = viewportWidthFor(orientation);
    final height = viewportHeightFor(orientation);
    if (width == null || height == null) return null;
    return '${width.toInt()} × ${height.toInt()}';
  }
}
