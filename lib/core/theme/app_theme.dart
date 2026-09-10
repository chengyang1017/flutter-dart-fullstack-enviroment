import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

abstract final class AppThemeController {
  static const String _boxName = 'app_preferences';
  static const String _deepNightKey = 'deep_night_mode';

  static final ValueNotifier<bool> deepNight = ValueNotifier<bool>(true);

  static Future<void> initialize() async {
    final box = Hive.isBoxOpen(_boxName)
        ? Hive.box<dynamic>(_boxName)
        : await Hive.openBox<dynamic>(_boxName);

    deepNight.value = box.get(_deepNightKey, defaultValue: true) == true;
  }

  static Future<void> toggle() async {
    await setDeepNight(!deepNight.value);
  }

  static Future<void> setDeepNight(bool value) async {
    if (deepNight.value == value) return;

    deepNight.value = value;

    if (Hive.isBoxOpen(_boxName)) {
      await Hive.box<dynamic>(_boxName).put(_deepNightKey, value);
    }
  }
}

abstract final class AppThemeData {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff3f74a6),
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xfff8fafc),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xfff5f7fb),
      surfaceContainer: const Color(0xffeef2f7),
      surfaceContainerHigh: const Color(0xffe8edf4),
      surfaceContainerHighest: const Color(0xffdfe6ef),
      outline: const Color(0xff8a95a5),
      outlineVariant: const Color(0xffd3dae5),
      onSurface: const Color(0xff1f2937),
      onSurfaceVariant: const Color(0xff5f6b7a),
      primary: const Color(0xff356a9c),
      onPrimary: Colors.white,
    );

    return _baseTheme(
      scheme: scheme,
      scaffoldBackground: const Color(0xfff5f7fb),
      cardColor: Colors.white,
      shadowColor: Colors.black.withValues(alpha: .12),
    );
  }

  static ThemeData get deepNight {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff82aaff),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xff111318),
      surfaceContainerLowest: const Color(0xff090c10),
      surfaceContainerLow: const Color(0xff0d1015),
      surfaceContainer: const Color(0xff15191f),
      surfaceContainerHigh: const Color(0xff1c222b),
      surfaceContainerHighest: const Color(0xff232b36),
      outline: const Color(0xff586273),
      outlineVariant: const Color(0xff2b333e),
      onSurface: const Color(0xffd7dde8),
      onSurfaceVariant: const Color(0xff9aa5b5),
      primary: const Color(0xff82aaff),
      onPrimary: const Color(0xff07111d),
    );

    return _baseTheme(
      scheme: scheme,
      scaffoldBackground: const Color(0xff0d1015),
      cardColor: const Color(0xff15191f),
      shadowColor: Colors.black.withValues(alpha: .48),
    );
  }

  static ThemeData _baseTheme({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color cardColor,
    required Color shadowColor,
  }) {
    final dark = scheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: scheme.surface,
      cardColor: cardColor,
      dividerColor: scheme.outlineVariant,
      shadowColor: shadowColor,
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: dark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
          surfaceTintColor:
              const WidgetStatePropertyAll<Color>(Colors.transparent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle:
            TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: .7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            dark ? const Color(0xff232b36) : const Color(0xff263241),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: const Color(0xff9dc2ff),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xff232b36) : const Color(0xff263241),
          borderRadius: BorderRadius.circular(7),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    );
  }
}

class AppThemeToggleButton extends StatelessWidget {
  const AppThemeToggleButton({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppThemeController.deepNight,
      builder: (context, deepNight, _) {
        final scheme = Theme.of(context).colorScheme;

        return IconButton(
          key: const ValueKey('app-theme-toggle'),
          tooltip: deepNight ? '切换浅色模式' : '切换深夜模式',
          onPressed: () {
            AppThemeController.toggle();
          },
          padding: EdgeInsets.zero,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 34, height: 34)
              : const BoxConstraints.tightFor(width: 42, height: 42),
          iconSize: compact ? 18 : 21,
          color: scheme.onSurfaceVariant,
          icon: Icon(
            deepNight ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
        );
      },
    );
  }
}
