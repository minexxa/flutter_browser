import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/shell_page.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(const BrowserApp());
}

class BrowserApp extends StatelessWidget {
  const BrowserApp({super.key});

  static const Color _seedColor = Color(0xFF1A73E8);

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Flutter 浏览器',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seedColor,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              scrolledUnderElevation: 1,
              centerTitle: true,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: _seedColor,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              elevation: 0,
              scrolledUnderElevation: 1,
              centerTitle: true,
            ),
          ),
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          home: const ShellPage(),
        );
      },
    );
  }
}
