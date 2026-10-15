import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_android_browser/pages/home_page.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('首页渲染搜索框、快捷访问与最近浏览', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            onSearch: (_) {},
            onOpenUrl: (_) {},
            onOpenSettings: () {},
            onOpenDownloads: () {},
            onClearHistory: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('搜索或输入网址'), findsOneWidget);
    expect(find.text('快捷访问'), findsOneWidget);
    // 默认快捷网址
    expect(find.text('百度'), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsOneWidget);

    // 最近浏览在视口下方，滚动后出现
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('最近浏览'), findsOneWidget);
  });
}
