import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';
import 'screens/auth.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await Api.create();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(api, prefs),
      child: const CleanHouseApp(),
    ),
  );
}

class CleanHouseApp extends StatelessWidget {
  const CleanHouseApp({super.key});
  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>((s) => s.themeMode);
    final lang = context.select<AppState, String>((s) => s.lang);
    return MaterialApp(
      title: 'CleanHouse',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(lang),
      darkTheme: buildDarkTheme(lang),
      themeMode: themeMode,
      // Scaffold does not wrap its body in a Material, so Text widgets in
      // screen bodies fall back to DefaultTextStyle.fallback() — which renders
      // the dreaded yellow underline. Wrapping every route in a transparent
      // Material gives the whole tree the theme's (decoration-stripped) text
      // style and kills the yellow lines globally.
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final status = context.select<AppState, AuthStatus>((s) => s.status);
    return switch (status) {
      AuthStatus.loading => Scaffold(
          backgroundColor: context.ch.pageBg,
          body: const Loader(),
        ),
      AuthStatus.loggedOut => const AuthScreen(),
      AuthStatus.loggedIn => const AppShell(),
    };
  }
}
