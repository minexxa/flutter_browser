import 'package:webview_flutter/webview_flutter.dart';

/// 浏览器标签页
class BrowserTab {
  BrowserTab({
    required this.id,
    required this.controller,
    this.isHome = true,
    this.title = '新标签页',
    this.url = '',
    this.isLoading = false,
    this.progress = 0,
    this.desktopMode = false,
  });

  final String id;
  final WebViewController controller;
  bool isHome; // 是否停留在首页
  String title;
  String url;
  bool isLoading;
  int progress;

  /// 是否对该标签使用电脑版 UA
  bool desktopMode;
}
