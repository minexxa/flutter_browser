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

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final seedColor = Color(settings.themeColor);
        final app = MaterialApp(
          title: 'Flutter 浏览器',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: seedColor,
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
              seedColor: seedColor,
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
          home: ShellPage(key: shellPageKey),
        );
        if (!settings.eyeCare) return app;
        // 护眼模式：全局叠加暖色滤镜
        return Stack(
          children: [
            app,
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Color(0x1FFF9800)),
              ),
            ),
          ],
        );
      },
    );
  }
}
