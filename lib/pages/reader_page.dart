import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 阅读模式页：以简洁排版展示提取出的正文
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.title, required this.html});

  final String title;
  final String html;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.dataFromString(
          _wrap(widget.title, widget.html),
          mimeType: 'text/html',
          encoding: utf8,
        ),
      );
  }

  static String _wrap(String title, String html) {
    final safeTitle = title
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle</title>
<style>
  body { max-width: 720px; margin: 0 auto; padding: 20px 18px 48px;
         font-size: 17px; line-height: 1.85; color: #222;
         word-break: break-word; background: #fff; }
  h1 { font-size: 22px; line-height: 1.4; margin: 0 0 16px; }
  h2, h3 { line-height: 1.5; }
  img { max-width: 100%; height: auto; border-radius: 6px; }
  pre { overflow: auto; padding: 12px; background: #f5f5f5; border-radius: 8px; }
  blockquote { margin: 12px 0; padding: 4px 14px; color: #666;
               border-left: 3px solid #ddd; }
  a { color: #1a73e8; text-decoration: none; }
  table { border-collapse: collapse; width: 100%; }
  td, th { border: 1px solid #e0e0e0; padding: 6px 8px; }
</style>
</head>
<body>
<h1>$safeTitle</h1>
$html
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title.isEmpty ? '阅读模式' : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
