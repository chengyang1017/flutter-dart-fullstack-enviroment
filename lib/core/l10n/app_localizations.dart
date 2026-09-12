import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

abstract final class AppLocaleController {
  static const String _boxName = 'app_preferences';
  static const String _localeKey = 'locale';

  static final ValueNotifier<Locale> locale =
      ValueNotifier<Locale>(const Locale('zh'));

  static Future<void> initialize() async {
    final box = Hive.isBoxOpen(_boxName)
        ? Hive.box<dynamic>(_boxName)
        : await Hive.openBox<dynamic>(_boxName);
    final stored = box.get(_localeKey, defaultValue: 'zh')?.toString();
    locale.value = Locale(stored == 'en' ? 'en' : 'zh');
  }

  static Future<void> toggle() async {
    await setLocale(locale.value.languageCode == 'en'
        ? const Locale('zh')
        : const Locale('en'));
  }

  static Future<void> setLocale(Locale value) async {
    final normalized = Locale(value.languageCode == 'en' ? 'en' : 'zh');
    if (locale.value == normalized) return;

    locale.value = normalized;
    if (Hive.isBoxOpen(_boxName)) {
      await Hive.box<dynamic>(_boxName).put(_localeKey, normalized.languageCode);
    }
  }
}

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  bool get isEnglish => locale.languageCode == 'en';

  String tr(String zh, String en) => isEnglish ? en : zh;

  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(localizations != null, 'AppLocalizations is not available.');
    return localizations!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
  ];
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'zh' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class AppLanguageToggleButton extends StatelessWidget {
  const AppLanguageToggleButton({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocaleController.locale,
      builder: (context, locale, _) {
        final scheme = Theme.of(context).colorScheme;
        final isEnglish = locale.languageCode == 'en';

        return IconButton(
          key: const ValueKey('app-language-toggle'),
          tooltip: isEnglish ? '切换到中文' : 'Switch to English',
          onPressed: AppLocaleController.toggle,
          padding: EdgeInsets.zero,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 40, height: 34)
              : const BoxConstraints.tightFor(width: 46, height: 42),
          color: scheme.onSurfaceVariant,
          icon: Text(
            isEnglish ? '中' : 'EN',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

class AppAppearanceActions extends StatelessWidget {
  const AppAppearanceActions({
    super.key,
    this.compact = false,
    required this.themeButton,
  });

  final bool compact;
  final Widget themeButton;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppLanguageToggleButton(compact: compact),
          themeButton,
        ],
      );
}
