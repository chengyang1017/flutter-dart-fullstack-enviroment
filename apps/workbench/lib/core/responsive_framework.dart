import 'package:flutter/material.dart';

/// 响应式设计框架
/// 定义统一的断点、尺寸和 helper 方法
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  /// 屏幕宽度断点
  static const double mobile = 600; // 手机: < 600px
  static const double tablet = 900; // 平板: 600-900px
  static const double desktop = 1200; // 桌面: >= 1200px
  static const double wideDesktop = 1800; // 超宽: >= 1800px

  /// 获取设备类型
  static DeviceType getDeviceType(double width) {
    if (width < mobile) return DeviceType.phone;
    if (width < tablet) return DeviceType.tablet;
    if (width < desktop) return DeviceType.desktop;
    if (width < wideDesktop) return DeviceType.desktop;
    return DeviceType.wideDesktop;
  }

  /// 获取设备方向描述
  static String getDeviceTypeLabel(DeviceType type) {
    switch (type) {
      case DeviceType.phone:
        return '手机';
      case DeviceType.tablet:
        return '平板';
      case DeviceType.desktop:
        return '桌面';
      case DeviceType.wideDesktop:
        return '超宽屏';
    }
  }
}

/// 设备类型枚举
enum DeviceType { phone, tablet, desktop, wideDesktop }

/// 响应式值处理器
class ResponsiveValue<T> {
  ResponsiveValue({
    required T phone,
    T? tablet,
    T? desktop,
    T? wideDesktop,
  })  : _phone = phone,
        _tablet = tablet ?? phone,
        _desktop = desktop ?? tablet ?? phone,
        _wideDesktop = wideDesktop ?? desktop ?? tablet ?? phone;

  final T _phone;
  final T _tablet;
  final T _desktop;
  final T _wideDesktop;

  /// 获取对应设备类型的值
  T getValue(DeviceType type) {
    switch (type) {
      case DeviceType.phone:
        return _phone;
      case DeviceType.tablet:
        return _tablet;
      case DeviceType.desktop:
        return _desktop;
      case DeviceType.wideDesktop:
        return _wideDesktop;
    }
  }

  /// 快速获取基于宽度的值
  T getByWidth(double width) {
    final type = ResponsiveBreakpoints.getDeviceType(width);
    return getValue(type);
  }
}

/// 响应式上下文扩展
extension ResponsiveMediaQueryExt on MediaQueryData {
  /// 是否是手机尺寸
  bool get isPhone => size.width < ResponsiveBreakpoints.mobile;

  /// 是否是平板尺寸
  bool get isTablet =>
      size.width >= ResponsiveBreakpoints.mobile &&
      size.width < ResponsiveBreakpoints.tablet;

  /// 是否是桌面尺寸
  bool get isDesktop => size.width >= ResponsiveBreakpoints.tablet;

  /// 是否是超宽屏
  bool get isWideDesktop => size.width >= ResponsiveBreakpoints.wideDesktop;

  /// 获取设备类型
  DeviceType get deviceType => ResponsiveBreakpoints.getDeviceType(size.width);

  /// 获取设备类型标签
  String get deviceTypeLabel =>
      ResponsiveBreakpoints.getDeviceTypeLabel(deviceType);
}

/// BuildContext 响应式扩展
extension ResponsiveContextExt on BuildContext {
  /// 媒体查询数据
  MediaQueryData get media => MediaQuery.of(this);

  /// 是否是手机
  bool get isPhone => media.isPhone;

  /// 是否是平板
  bool get isTablet => media.isTablet;

  /// 是否是桌面
  bool get isDesktop => media.isDesktop;

  /// 是否是超宽屏
  bool get isWideDesktop => media.isWideDesktop;

  /// 设备类型
  DeviceType get deviceType => media.deviceType;

  /// 设备类型标签
  String get deviceTypeLabel => media.deviceTypeLabel;

  /// 屏幕宽度
  double get screenWidth => media.size.width;

  /// 屏幕高度
  double get screenHeight => media.size.height;

  /// 设备像素比
  double get devicePixelRatio => media.devicePixelRatio;
}

/// 响应式布局构建器
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.phone,
    this.tablet,
    this.desktop,
    this.wideDesktop,
  });

  /// 完整构建函数，接收设备类型和约束
  final Widget Function(BuildContext context, DeviceType deviceType,
      BoxConstraints constraints) builder;

  /// 手机布局构建器（可选简化）
  final Widget Function(BuildContext context)? phone;

  /// 平板布局构建器（可选简化）
  final Widget Function(BuildContext context)? tablet;

  /// 桌面布局构建器（可选简化）
  final Widget Function(BuildContext context)? desktop;

  /// 超宽屏布局构建器（可选简化）
  final Widget Function(BuildContext context)? wideDesktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final deviceType =
            ResponsiveBreakpoints.getDeviceType(constraints.maxWidth);

        // 使用简化构建器（如果提供）
        if (phone != null && deviceType == DeviceType.phone) {
          return phone!(context);
        }
        if (tablet != null && deviceType == DeviceType.tablet) {
          return tablet!(context);
        }
        if (desktop != null &&
            (deviceType == DeviceType.desktop ||
                deviceType == DeviceType.wideDesktop)) {
          return desktop!(context);
        }
        if (wideDesktop != null && deviceType == DeviceType.wideDesktop) {
          return wideDesktop!(context);
        }

        // 使用完整构建器
        return builder(context, deviceType, constraints);
      },
    );
  }
}

/// 最大宽度约束容器
class MaxWidthContainer extends StatelessWidget {
  const MaxWidthContainer({
    super.key,
    required this.child,
    this.maxWidth = 1400,
    this.padding = const EdgeInsets.all(16),
    this.center = true,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final widget = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (center) {
      return Center(child: widget);
    }
    return widget;
  }
}

/// 响应式间距助手
class ResponsiveSpacing {
  ResponsiveSpacing._();

  /// 获取响应式间距
  static double get(
    BuildContext context, {
    double phone = 8,
    double tablet = 12,
    double desktop = 16,
    double wideDesktop = 20,
  }) {
    final type = context.deviceType;
    switch (type) {
      case DeviceType.phone:
        return phone;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.desktop:
        return desktop;
      case DeviceType.wideDesktop:
        return wideDesktop;
    }
  }

  /// 获取响应式内边距
  static EdgeInsets getPadding(
    BuildContext context, {
    double phone = 16,
    double tablet = 20,
    double desktop = 24,
    double wideDesktop = 32,
  }) {
    final spacing = get(
      context,
      phone: phone,
      tablet: tablet,
      desktop: desktop,
      wideDesktop: wideDesktop,
    );
    return EdgeInsets.all(spacing);
  }

  /// 获取响应式文字大小
  static double getTextSize(
    BuildContext context, {
    double phone = 14,
    double tablet = 15,
    double desktop = 16,
    double wideDesktop = 17,
  }) {
    final type = context.deviceType;
    switch (type) {
      case DeviceType.phone:
        return phone;
      case DeviceType.tablet:
        return tablet;
      case DeviceType.desktop:
        return desktop;
      case DeviceType.wideDesktop:
        return wideDesktop;
    }
  }
}

/// 响应式网格
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.phoneColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.wideDesktopColumns = 4,
    this.spacing = 16,
  });

  final List<Widget> children;
  final int phoneColumns;
  final int tabletColumns;
  final int desktopColumns;
  final int wideDesktopColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final type = context.deviceType;
    final columns = switch (type) {
      DeviceType.phone => phoneColumns,
      DeviceType.tablet => tabletColumns,
      DeviceType.desktop => desktopColumns,
      DeviceType.wideDesktop => wideDesktopColumns,
    };

    return GridView.count(
      crossAxisCount: columns,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      children: children,
    );
  }
}
