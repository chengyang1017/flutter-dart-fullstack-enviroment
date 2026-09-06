enum RunnerPreviewTarget {
  phone,
  tablet,
  web,
}

enum RunnerPreviewOrientation {
  portrait,
  landscape,
}

extension RunnerPreviewOrientationInfo on RunnerPreviewOrientation {
  String get label => switch (this) {
        RunnerPreviewOrientation.portrait => '竖屏',
        RunnerPreviewOrientation.landscape => '横屏',
      };
}

extension RunnerPreviewTargetInfo on RunnerPreviewTarget {
  String get label => switch (this) {
        RunnerPreviewTarget.phone => '手机',
        RunnerPreviewTarget.tablet => '平板',
        RunnerPreviewTarget.web => '网页',
      };

  String get description => switch (this) {
        RunnerPreviewTarget.phone => '在 IDE 内以 390 × 844 的手机视口运行',
        RunnerPreviewTarget.tablet => '在 IDE 内以 820 × 1180 的平板视口运行',
        RunnerPreviewTarget.web => '运行完成后在新的浏览器标签页打开',
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
