import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/l10n/app_localizations.dart';
import '../core/navigation/monaco_route_observer.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/screens/workspace_auth_screen.dart';
import '../features/auth/widgets/claim_existing_account_dialog.dart';
import '../features/home/screens/home_screen.dart';
import '../features/workspace/services/workspace_auth_runtime.dart';

class PlaygroundApp extends StatefulWidget {
  const PlaygroundApp({super.key});

  @override
  State<PlaygroundApp> createState() => _PlaygroundAppState();
}

class _PlaygroundAppState extends State<PlaygroundApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    AppThemeController.deepNight.addListener(_handleAppearanceChanged);
    AppLocaleController.locale.addListener(_handleAppearanceChanged);
  }

  void _handleAppearanceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppThemeController.deepNight.removeListener(_handleAppearanceChanged);
    AppLocaleController.locale.removeListener(_handleAppearanceChanged);
    super.dispose();
  }

  Future<void> _login({
    required String email,
    required String password,
  }) async {
    await WorkspaceAuthRuntime.login(
      email: email,
      password: password,
    );
    if (mounted) setState(() {});
  }

  Future<void> _register({
    required String username,
    required String email,
    required String password,
  }) async {
    await WorkspaceAuthRuntime.register(
      username: username,
      email: email,
      password: password,
    );
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    await WorkspaceAuthRuntime.logout();
    if (mounted) setState(() {});
  }

  Future<void> _showClaimExistingAccount() async {
    final identity = WorkspaceAuthRuntime.identity;
    final dialogContext = _navigatorKey.currentContext;
    if (identity == null ||
        !WorkspaceAuthRuntime.canClaimExistingAccount ||
        dialogContext == null) {
      return;
    }

    final claimed = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => ClaimExistingAccountDialog(
        username: identity.accountNamespace,
        onClaim: ({required String email, required String password}) =>
            WorkspaceAuthRuntime.claimExistingAccount(
          email: email,
          password: password,
        ),
      ),
    );
    if (claimed == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloudConfigured = WorkspaceAuthRuntime.cloudConfigured;
    final identity = WorkspaceAuthRuntime.identity;

    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [monacoRouteObserver],
      title: 'Flutter UI Playground',
      debugShowCheckedModeBanner: false,
      theme: AppThemeData.light,
      darkTheme: AppThemeData.deepNight,
      themeMode:
          AppThemeController.deepNight.value ? ThemeMode.dark : ThemeMode.light,
      locale: AppLocaleController.locale.value,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: cloudConfigured && identity == null
          ? WorkspaceAuthScreen(
              initialError: WorkspaceAuthRuntime.startupError?.toString(),
              onLogin: _login,
              onRegister: _register,
            )
          : HomeScreen(
              username: identity?.accountNamespace,
              onClaimAccount: WorkspaceAuthRuntime.canClaimExistingAccount
                  ? _showClaimExistingAccount
                  : null,
              onLogout: identity == null ? null : _logout,
            ),
    );
  }
}
