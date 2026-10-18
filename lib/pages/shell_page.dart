import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/browser_tab.dart';
import '../pages/bookmarks_page.dart';
import '../pages/downloads_page.dart';
import '../pages/history_page.dart';
import '../pages/home_page.dart';
import '../pages/reader_page.dart';
import '../pages/search_settings_page.dart';
import '../pages/settings_page.dart';
import '../pages/site_settings_page.dart';
import '../pages/sniffer_page.dart';
import '../pages/tabs_page.dart';
import '../services/ad_rule_service.dart';
import '../services/browser_data_service.dart';
import '../services/download_service.dart';
import '../services/quick_engine_service.dart';
import '../services/settings_service.dart';
import '../services/site_settings_service.dart';
import '../services/sniffer_service.dart';
import '../utils/js_injections.dart';
import '../utils/url_utils.dart';
import '../utils/webview_ext.dart';

/// 主界面：首页 / 网页浏览 切换 + 多标签 + 底部工具栏
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => ShellPageState();
}

/// 供书签 / 历史等子页面从任意位置打开网址
final GlobalKey<ShellPageState> shellPageKey = GlobalKey<ShellPageState>();

class ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  static const String _volumeChannelName =
      'com.example.flutter_android_browser/volume';
  static const String _cookieChannelName =
      'com.example.flutter_android_browser/cookies';
  /// 地址栏建议面板 Key（供测试定位）
  static const Key suggestionPanelKey = Key('suggestion_panel');
  static const MethodChannel _cookieChannel = MethodChannel(_cookieChannelName);

  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final MethodChannel _volumeChannel = const MethodChannel(_volumeChannelName);

  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _appReady = false;
  bool _finding = false;
  String _findCount = '0/0';
  double? _edgeDragStartX;
  final TextEditingController _findController = TextEditingController();

  // 地址栏建议
  final List<String> _suggestions = [];
  bool _suggestionOpen = false;
  bool _suggestionLoading = false;
  int _suggestionRequestId = 0;
  bool? _appliedCookieAccept;

  BrowserTab get _currentTab => _tabs[_currentIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SettingsService.instance.addListener(_onSettingsChanged);
    _urlFocusNode.addListener(_onUrlFocusChanged);
    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.instance.removeListener(_onSettingsChanged);
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    _volumeChannel.setMethodCallHandler(null);
    _urlController.dispose();
    _urlFocusNode.dispose();
    _findController.dispose();
    _suggestionDebounce?.cancel();
    _suggestionHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    try {
      await SettingsService.instance.load();
      await QuickEngineService.instance.init();
      await DownloadService.instance.init();
      await AdRuleService.instance.init();
      await SiteSettingsService.instance.init();
      _setupVolumeChannel();
      // 屏幕常亮不阻塞启动：channel 异常静默降级
      WakelockPlus.toggle(enable: SettingsService.instance.keepScreenOn)
          .catchError((_) {});
      await _applyCookieAccept(SettingsService.instance.cookieAccept);

      final settings = SettingsService.instance;
      if (settings.startPage == 'restore') {
        final saved = await BrowserDataService.instance.loadOpenTabs();
        for (final item in saved) {
          if (!mounted) return;
          final url = item['url'] ?? '';
          if (url.isNotEmpty) {
            await _addTab(url: url, title: item['title'] ?? '新标签页');
          }
        }
      } else if (settings.startPage == 'custom' &&
          settings.startPageUrl.isNotEmpty) {
        if (!mounted) return;
        await _addTab(url: settings.startPageUrl, title: '新标签页');
      }
      if (_tabs.isEmpty) {
        if (!mounted) return;
        await _addTab();
      }
    } catch (e, stack) {
      // 初始化任一步骤失败都不阻塞 UI：记录日志并兜底创建标签页，
      // 保证界面可见（否则 _appReady 永远为 false，表现为白屏）
      debugPrint('应用初始化异常（UI 仍将渲染）: $e\n$stack');
      if (!mounted) return;
      if (_tabs.isEmpty) {
        try {
          await _addTab();
        } catch (e2) {
          debugPrint('兜底创建标签页失败: $e2');
        }
      }
    }
    if (!mounted) return;
    setState(() => _appReady = true);
    _applyFullscreen();
  }

  // ---- 音量键翻页 ----

  Future<void> _setupVolumeChannel() async {
    _volumeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeKey') {
        final args = call.arguments;
        final down = args is Map && args['down'] == true;
        _scrollWebView(down: down);
      }
      return null;
    });
    await _setVolumeScrollEnabled(SettingsService.instance.volumeKeyScroll);
  }

  Future<void> _setVolumeScrollEnabled(bool enabled) async {
    try {
      await _volumeChannel.invokeMethod('setVolumeScrollEnabled', enabled);
    } catch (_) {}
  }

  /// 全局 Cookie 开关（经原生 CookieManager 实时生效）
  Future<void> _applyCookieAccept(bool accept) async {
    if (_appliedCookieAccept == accept) return;
    _appliedCookieAccept = accept;
    try {
      await _cookieChannel.invokeMethod('setAcceptCookie', accept);
    } catch (_) {}
  }

  void _scrollWebView({required bool down}) {
    if (_tabs.isEmpty || _currentTab.isHome) return;
    final delta = down ? 320 : -320;
    _currentTab.controller.runJavaScript('window.scrollBy(0, $delta);');
  }

  // ---- 设置变更 ----

  void _onSettingsChanged() {
    if (!mounted || _tabs.isEmpty) return;
    final settings = SettingsService.instance;
    _applyFullscreen();
    _setVolumeScrollEnabled(settings.volumeKeyScroll);
    WakelockPlus.toggle(enable: settings.keepScreenOn);
    _applyCookieAccept(settings.cookieAccept);
    for (final tab in _tabs) {
      applyFontSize(tab.controller, settings.fontSize.textZoom);
      applyForceZoom(tab.controller, settings.forceZoom);
      applyMediaGesture(tab.controller, settings.saveData);
      applyGeolocationEnabled(tab.controller, settings.geolocationAccess);
    }
    // 广告拦截 / 无图 / 强制缩放变更后对当前页重新注入
    if (!_currentTab.isHome) {
      _injectScripts(_currentTab);
    }
    // 搜索工具栏 / 标签栏 / 地址栏内容等 UI 开关需要重建
    setState(() {});
  }

  void _applyFullscreen() {
    if (SettingsService.instance.fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ---- 标签管理 ----

  Future<void> _addTab({
    String url = '',
    String title = '新标签页',
    bool incognito = false,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final tab = BrowserTab(
      id: id,
      controller: WebViewController(),
      isHome: url.isEmpty,
      title: incognito && url.isEmpty ? '无痕标签页' : title,
      url: url,
      incognito: incognito,
    );

    final settings = SettingsService.instance;
    final backgroundColor = mounted
        ? Theme.of(context).colorScheme.surface
        : const Color(0xFFFFFFFF);
    // 平台配置失败不阻塞标签页创建：WebView 仍可用，仅个别设置降级
    // （未兜底时此处异常会中断 _initApp，导致 _appReady 不置位而白屏）
    try {
      await tab.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tab.controller.setBackgroundColor(backgroundColor);
      await tab.controller.setNavigationDelegate(_buildNavigationDelegate(tab));

      // 用户滑动网页即收起地址栏：平台视图（WebView）的触摸不透传 Flutter 焦点系统，
      // 若不监听滚动主动收起，聚焦地址栏后建议面板+软键盘会常驻压缩 WebView 可视区
      final android = androidControllerOf(tab.controller);
      if (android != null) {
        await android.setOnScrollPositionChange((_) => _collapseUrlBar());
      }

      await tab.controller.addJavaScriptChannel(
        'DownloadBridge',
        onMessageReceived: _onDownloadBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'PasswordBridge',
        onMessageReceived: _onPasswordBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'ClipboardBridge',
        onMessageReceived: _onClipboardBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'ImageBridge',
        onMessageReceived: _onImageBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'FindBridge',
        onMessageReceived: _onFindBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'ReaderBridge',
        onMessageReceived: _onReaderBridgeMessage,
      );
      await tab.controller.addJavaScriptChannel(
        'ResourceBridge',
        onMessageReceived: (message) => _onResourceBridgeMessage(tab, message),
      );
      await tab.controller.setUserAgent(_effectiveUA(tab));
      applyFontSize(tab.controller, settings.fontSize.textZoom);
      applyForceZoom(tab.controller, settings.forceZoom);
      applyMediaGesture(tab.controller, settings.saveData);
      applyGeolocationEnabled(tab.controller, settings.geolocationAccess);
      await _applySiteSettings(tab);
    } catch (e) {
      debugPrint('WebView 平台配置失败（标签页仍可用）: $e');
    }

    _tabs.add(tab);
    _currentIndex = _tabs.length - 1;
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await tab.controller.loadRequest(uri);
      }
    }
    if (!mounted) return;
    setState(() {});
    _updateNavState();
  }

  NavigationDelegate _buildNavigationDelegate(BrowserTab tab) {
    return NavigationDelegate(
      onProgress: (int progress) {
        if (!mounted) return;
        setState(() {
          tab.progress = progress;
          tab.isLoading = progress < 100;
        });
      },
      onPageStarted: (String url) {
        if (!mounted) return;
        // 页面开始导航即收起地址栏编辑态：聚焦地址栏后点网页内链接，
        // 平台视图触摸不会失焦，需主动收起（否则面板+键盘常驻压缩 WebView）
        _collapseUrlBar();
        setState(() {
          tab.url = url;
          tab.isLoading = true;
          tab.isHome = false;
          if (!_urlFocusNode.hasFocus) {
            _urlController.text = _displayUrlFor(tab);
          }
        });
        // 站点变化时同步站点设置（JS / Cookie）
        _applySiteSettings(tab);
        // 新导航开始，清空上一页嗅探到的资源
        SnifferService.instance.clearTab(tab.id);
      },
      onPageFinished: (String url) async {
        if (!mounted) return;
        // 兜底：部分导航（如 JS 重定向/历史跳转）只触发 finished，
        // 同样收起地址栏编辑态，避免面板+键盘常驻压缩 WebView
        _collapseUrlBar();
        String title = tab.title;
        try {
          final loaded = await tab.controller.getTitle();
          if (loaded != null && loaded.isNotEmpty) title = loaded;
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          tab.title = title;
          tab.url = url;
          tab.isLoading = false;
          if (!_urlFocusNode.hasFocus) {
            _urlController.text = _displayUrlFor(tab);
          }
        });
        if (!tab.incognito) {
          BrowserDataService.instance.addHistory(url, title);
        }
        await _injectScripts(tab);
        await _fillSavedPassword(tab);
        _updateNavState();      },
      onWebResourceError: (WebResourceError error) {
        debugPrint('WebView 错误: ${error.description}');
      },
      onNavigationRequest: (NavigationRequest request) {
        if (request.isMainFrame) {
          final tabHost = SiteSettingsService.hostOf(tab.url);
          final adOn = SiteSettingsService.instance
              .adBlockEnabled(tabHost, SettingsService.instance.adBlock);
          if (adOn && _isAdHost(request.url)) {
            return NavigationDecision.prevent;
          }
          if (looksDownloadable(request.url)) {
            // 主框架导航到可下载资源时交给内置下载器
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showDownloadDialog(request.url);
            });
            return NavigationDecision.prevent;
          }
        }
        return NavigationDecision.navigate;
      },
    );
  }

  String? _effectiveUA(BrowserTab tab) {
    final host = SiteSettingsService.hostOf(tab.url);
    if (host.isNotEmpty) {
      final override = SiteSettingsService.instance.userAgentOverride(host);
      if (override != null) return override;
    }
    if (tab.desktopMode) return BrowserIdentity.byKey('pc').userAgent;
    return SettingsService.instance.effectiveUserAgent;
  }

  /// 应用站点设置：JS 开关 / Cookie 开关
  Future<void> _applySiteSettings(BrowserTab tab) async {
    if (tab.isHome) return;
    final host = SiteSettingsService.hostOf(tab.url);
    if (host.isEmpty) return;
    final site = SiteSettingsService.instance;
    final android = androidControllerOf(tab.controller);
    if (android != null) {
      try {
        await android.setJavaScriptMode(
          site.javaScriptEnabled(host)
              ? JavaScriptMode.unrestricted
              : JavaScriptMode.disabled,
        );
      } catch (_) {}
    }
    await _setCookieAccept(site.cookiesEnabled(host));
  }

  Future<void> _setCookieAccept(bool accept) async {
    try {
      await _cookieChannel.invokeMethod('setAcceptCookie', accept);
    } catch (_) {}
  }

  /// 供网站设置页调用：应用最新站点设置并重载当前页
  Future<void> applySiteSettingsAndReload() async {
    final tab = _currentTab;
    if (tab.isHome) return;
    try {
      await tab.controller.setUserAgent(_effectiveUA(tab));
    } catch (_) {}
    await _applySiteSettings(tab);
    tab.controller.reload();
  }

  bool _isAdHost(String url) => AdRuleService.instance.isAdHost(url);

  Future<void> _injectScripts(BrowserTab tab) async {
    if (tab.isHome) return;
    final settings = SettingsService.instance;
    final script = buildPageFinishedScript(
      adBlock: settings.adBlock,
      noImage: settings.noImage,
      saveData: settings.saveData,
      forceZoom: settings.forceZoom,
      passwordCapture: settings.savePassword,
      clipboardOverride: settings.clipboardAccess,
    );
    try {
      await tab.controller.runJavaScript(script);
    } catch (_) {}
    // 搜索引擎快捷切换栏（移植自《移动端搜索引擎快捷切换》userscript）
    if (settings.searchToolbar && isSearchEngineUrl(tab.url)) {
      try {
        await tab.controller.runJavaScript(
          buildEngineSwitcherScript(QuickEngineService.instance.engines),
        );
      } catch (_) {}
    }
    // 站点级图片阻止
    final host = SiteSettingsService.hostOf(tab.url);
    if (host.isNotEmpty && SiteSettingsService.instance.imagesBlocked(host)) {
      try {
        await tab.controller.runJavaScript(kSiteNoImageJs);
      } catch (_) {}
    }
  }

  /// 对已保存凭据的站点自动填充密码
  Future<void> _fillSavedPassword(BrowserTab tab) async {
    if (!SettingsService.instance.savePassword) return;
    final host = Uri.tryParse(tab.url)?.host ?? '';
    if (host.isEmpty) return;
    final passwords = await BrowserDataService.instance.savedPasswords();
    final entry = passwords[host];
    if (entry == null) return;
    final script = passwordFillScript(
      entry['username'] ?? '',
      entry['password'] ?? '',
    );
    try {
      await tab.controller.runJavaScript(script);
    } catch (_) {}
  }

  // ---- JS 桥消息 ----

  void _onDownloadBridgeMessage(JavaScriptMessage message) {
    final url = message.message;
    if (url.isEmpty || url.startsWith('about:')) return;
    _showDownloadDialog(url);
  }

  void _onPasswordBridgeMessage(JavaScriptMessage message) {
    if (!SettingsService.instance.savePassword) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      if (data['action'] != 'save') return;
      final host = data['host'] as String? ?? '';
      final username = data['username'] as String? ?? '';
      final password = data['password'] as String? ?? '';
      if (host.isEmpty || username.isEmpty || password.isEmpty) return;
      _handleCapturedPassword(host, username, password);
    } catch (_) {}
  }

  Future<void> _handleCapturedPassword(
    String host,
    String username,
    String password,
  ) async {
    if (await BrowserDataService.instance.isNeverSaveHost(host)) return;
    // 与已保存的一致时不再打扰
    final saved = await BrowserDataService.instance.savedPasswords();
    final existing = saved[host];
    if (existing != null &&
        existing['username'] == username &&
        existing['password'] == password) {
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存密码？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('网站：$host'),
              const SizedBox(height: 4),
              Text('用户名：$username'),
              const SizedBox(height: 4),
              const Text('密码：••••••••'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await BrowserDataService.instance.addNeverSaveHost(host);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已设置此站不再询问')),
                );
              },
              child: const Text('永不保存'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await BrowserDataService.instance
                    .savePassword(host, username, password);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码已保存')),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _onClipboardBridgeMessage(JavaScriptMessage message) {
    if (!SettingsService.instance.clipboardAccess) return;
    final text = message.message;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  void _onImageBridgeMessage(JavaScriptMessage message) {
    final url = message.message;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    _showSaveImageDialog(url);
  }

  void _onFindBridgeMessage(JavaScriptMessage message) {
    if (!mounted) return;
    setState(() => _findCount = message.message);
  }

  void _onReaderBridgeMessage(JavaScriptMessage message) {
    if (!mounted) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final title = data['title'] as String? ?? '';
      final html = data['html'] as String? ?? '';
      if (html.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能提取到正文')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(title: title, html: html),
        ),
      );
    } catch (_) {}
  }

  void _onResourceBridgeMessage(BrowserTab tab, JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! List) return;
      final urls = decoded
          .whereType<String>()
          .where((e) => e.startsWith('http://') || e.startsWith('https://'))
          .toList();
      if (urls.isEmpty) return;
      SnifferService.instance.addAll(tab.id, urls);
    } catch (_) {}
  }

  // ---- 页内查找 ----

  void _startFind() {
    if (_currentTab.isHome) return;
    setState(() => _finding = true);
    _runFindJs(kFindInPageJs);
  }

  void _onFindChanged(String query) {
    if (query.isEmpty) {
      setState(() => _findCount = '0/0');
      _runFindJs('window.__viaFindClear && window.__viaFindClear();');
      return;
    }
    _runFindJs('window.__viaFind && window.__viaFind(${jsonEncode(query)});');
  }

  void _findNext() =>
      _runFindJs('window.__viaFindNext && window.__viaFindNext();');

  void _findPrev() =>
      _runFindJs('window.__viaFindPrev && window.__viaFindPrev();');

  void _runFindJs(String js) {
    if (_tabs.isEmpty || _currentTab.isHome) return;
    try {
      _currentTab.controller.runJavaScript(js);
    } catch (_) {}
  }

  void _stopFind() {
    _runFindJs('window.__viaFindClear && window.__viaFindClear();');
    if (!mounted) return;
    setState(() {
      _finding = false;
      _findCount = '0/0';
    });
    _findController.clear();
  }

  // ---- 网页工具 ----

  Future<void> _viewSource() async {
    final tab = _currentTab;
    if (tab.isHome) return;
    String source = '';
    try {
      final result = await tab.controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      source = result.toString();
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('网页源码'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                source.isEmpty ? '无法获取源码' : source,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showQrCode() {
    final url = _currentTab.url;
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('网页二维码'),
          content: SizedBox(
            width: 240,
            height: 240,
            child: Center(
              child: QrImageView(
                data: url,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _translatePage() {
    final tab = _currentTab;
    if (tab.isHome || tab.url.isEmpty) return;
    final target =
        'https://fanyi.baidu.com/transpage?query=${Uri.encodeComponent(tab.url)}&from=auto&to=zh&source=url';
    tab.isHome = false;
    tab.controller.loadRequest(Uri.parse(target));
    setState(() {});
  }

  void _openReaderMode() {
    final tab = _currentTab;
    if (tab.isHome) return;
    try {
      tab.controller.runJavaScript(kReaderExtractJs);
    } catch (_) {}
  }

  void _openSniffer() {
    final tab = _currentTab;
    if (tab.isHome) return;
    // 打开面板时主动触发一次即时嗅探
    try {
      tab.controller
          .runJavaScript('window.__viaSniff && window.__viaSniff();');
    } catch (_) {}
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SnifferPage(
          tabId: tab.id,
          onOpenInNewTab: (url) {
            _addTab(url: url);
          },
        ),
      ),
    );
  }

  Future<void> _sharePage() async {
    final url = _currentTab.url;
    if (url.isEmpty) return;
    try {
      await Share.shareUri(Uri.parse(url));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分享失败')),
      );
    }
  }

  Future<void> _addBookmark() async {
    final tab = _currentTab;
    if (tab.isHome || tab.url.isEmpty) return;
    final added =
        await BrowserDataService.instance.addBookmark(tab.title, tab.url);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已添加书签' : '书签已存在')),
    );
  }

  void _showSaveImageDialog(String url) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('保存图片'),
          content: Text(
            url,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await DownloadService.instance.startDownload(
                  url,
                  fileName: _fileNameFromUrl(url),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('图片已开始下载')),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  String _fileNameFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final last = segments.isNotEmpty ? segments.last : '';
    if (last.contains('.')) return last;
    return 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  // ---- 子页面导航 ----

  void _openBookmarks() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const BookmarksPage()),
    );
  }

  void _openSiteSettings() {
    final host = SiteSettingsService.hostOf(_currentTab.url);
    if (host.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SiteSettingsPage(host: host),
      ),
    );
  }

  void _openSearchSettings() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const SearchSettingsPage(),
      ),
    );
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
    );
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      final tab = _tabs[0];
      tab.isHome = true;
      tab.title = '新标签页';
      tab.url = '';
      tab.progress = 0;
      tab.isLoading = false;
      tab.controller.loadRequest(Uri.parse('about:blank'));
      if (!_urlFocusNode.hasFocus) _urlController.clear();
      setState(() {});
      return;
    }
    final removed = _tabs.removeAt(index);
    SnifferService.instance.clearTab(removed.id);
    if (_currentIndex >= _tabs.length) {
      _currentIndex = _tabs.length - 1;
    } else if (_currentIndex > index) {
      _currentIndex--;
    }
    setState(() {});
    _updateNavState();
  }

  void _switchTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _currentIndex = index;
      if (!_urlFocusNode.hasFocus) {
        _urlController.text = _displayUrlFor(_currentTab);
      }
    });
    // 查找条保持打开时，在新标签上重新执行当前关键字
    if (_finding && !_currentTab.isHome) {
      final query = _findController.text;
      if (query.isEmpty) {
        _runFindJs('window.__viaFindClear && window.__viaFindClear();');
      } else {
        _runFindJs(
            'window.__viaFind && window.__viaFind(${jsonEncode(query)});');
      }
    }
    _updateNavState();
  }

  /// 按"地址栏内容"设置计算地址栏显示文本（网址/域名/标题）
  String _displayUrlFor(BrowserTab tab) {
    final mode = SettingsService.instance.addressBarContent;
    if (mode == 'domain') {
      final host = hostOf(tab.url);
      return host.isEmpty ? tab.url : host;
    }
    if (mode == 'title') {
      return tab.title.isEmpty ? tab.url : tab.title;
    }
    return tab.url;
  }

  Future<void> _updateNavState() async {
    if (_tabs.isEmpty || !mounted) return;
    try {
      final canBack = await _currentTab.controller.canGoBack();
      final canForward = await _currentTab.controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = canBack;
        _canGoForward = canForward;
      });
    } catch (_) {}
  }

  // ---- 导航 ----

  void _openUrl(String input) => _submitInput(input);

  /// 统一输入提交：快捷词 / 搜索历史记录 / 加载
  void _submitInput(String input, {bool recordSearch = true}) {
    final settings = SettingsService.instance;
    final url = normalizeInput(
      input,
      engine: settings.effectiveSearchEngine,
      quickWords: settings.searchQuickWords,
      customSearchUrl: settings.customSearchUrl,
    );
    if (url.isEmpty) return;
    if (recordSearch &&
        settings.searchHistoryEnabled &&
        isPlainSearchQuery(input)) {
      BrowserDataService.instance.addSearchHistory(input.trim());
    }
    _urlFocusNode.unfocus();
    _hideSuggestions();
    final tab = _currentTab;
    tab.isHome = false;
    tab.controller.loadRequest(Uri.parse(url));
    setState(() {});
  }

  void _goHome() {
    final tab = _currentTab;
    final customHome = SettingsService.instance.homePage;
    if (customHome != 'default' && customHome.isNotEmpty) {
      // 设置了自定义主页：主页按钮加载该网址
      tab.isHome = false;
      tab.controller.loadRequest(Uri.parse(customHome));
      setState(() {});
      return;
    }
    if (tab.isHome) return;
    setState(() => tab.isHome = true);
  }

  void _onUrlSubmitted(String input) => _openUrl(input);

  /// 供书签 / 历史等子页面调用：关闭子页面并在当前标签打开网址
  void openUrlFromAnywhere(String url) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _openUrl(url);
  }

  // ---- 下载 ----

  void _showDownloadDialog(String url) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('要下载此资源吗？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                url,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await DownloadService.instance.startDownload(url);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已加入下载列表'),
                    action: SnackBarAction(
                      label: '查看',
                      onPressed: _openDownloads,
                    ),
                  ),
                );
              },
              child: const Text('下载'),
            ),
          ],
        );
      },
    );
  }

  // ---- 页面跳转 ----

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  void _openDownloads() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const DownloadsPage()),
    );
  }

  Future<void> _openTabsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TabsPage(
          tabs: _tabs,
          currentIndex: _currentIndex,
          onSelect: (index) {
            _switchTab(index);
            Navigator.pop(context);
          },
          onClose: (index) {
            setState(() => _closeTab(index));
          },
          onNewTab: () async {
            Navigator.pop(context);
            await _addTab();
          },
          onNewIncognito: () async {
            Navigator.pop(context);
            await _addTab(incognito: true);
          },
          onCloseAll: () {
            Navigator.pop(context);
            setState(() {
              _tabs.clear();
            });
            SnifferService.instance.clearAll();
            _addTab();
          },
        ),
      ),
    );
  }

  // ---- 菜单 ----

  void _showMainMenu() {
    final settings = SettingsService.instance;
    final notHome = !_currentTab.isHome && _currentTab.url.isNotEmpty;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: [
                        _menuItem(sheetContext, Icons.add, '新建标签页', () {
                          Navigator.pop(sheetContext);
                          _addTab();
                        }),
                        _menuItem(
                          sheetContext,
                          Icons.visibility_off_outlined,
                          '新建无痕标签页',
                          () {
                            Navigator.pop(sheetContext);
                            _addTab(incognito: true);
                          },
                        ),
                        _menuItem(
                            sheetContext, Icons.star_outline, '书签', () {
                          Navigator.pop(sheetContext);
                          _openBookmarks();
                        }),
                        _menuItem(
                            sheetContext, Icons.history, '历史记录', () {
                          Navigator.pop(sheetContext);
                          _openHistory();
                        }),
                        _menuItem(sheetContext, Icons.bookmark_add_outlined,
                            '添加收藏', () {
                          Navigator.pop(sheetContext);
                          _addBookmark();
                        }, enabled: notHome),
                        _menuItem(sheetContext, Icons.share_outlined, '分享',
                            () {
                          Navigator.pop(sheetContext);
                          _sharePage();
                        }, enabled: notHome),
                        _menuItem(sheetContext, Icons.copy_outlined, '复制网址',
                            () {
                          Navigator.pop(sheetContext);
                          _copyUrl();
                        }, enabled: notHome),
                        _menuItem(
                          sheetContext,
                          Icons.arrow_forward,
                          '前进',
                          () {
                            Navigator.pop(sheetContext);
                            _currentTab.controller.goForward();
                          },
                          enabled: _canGoForward,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.desktop_windows_outlined,
                          '桌面版网站',
                          () async {
                            Navigator.pop(sheetContext);
                            await _toggleDesktopMode();
                          },
                          enabled: notHome,
                          highlighted: _currentTab.desktopMode,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.tune,
                          '网站设置',
                          () {
                            Navigator.pop(sheetContext);
                            _openSiteSettings();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.manage_search,
                          '搜索设置',
                          () {
                            Navigator.pop(sheetContext);
                            _openSearchSettings();
                          },
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.search,
                          '页内查找',
                          () {
                            Navigator.pop(sheetContext);
                            _startFind();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.code,
                          '网页源码',
                          () {
                            Navigator.pop(sheetContext);
                            _viewSource();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.qr_code_2,
                          '生成二维码',
                          () {
                            Navigator.pop(sheetContext);
                            _showQrCode();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.translate,
                          '翻译网页',
                          () {
                            Navigator.pop(sheetContext);
                            _translatePage();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.chrome_reader_mode_outlined,
                          '阅读模式',
                          () {
                            Navigator.pop(sheetContext);
                            _openReaderMode();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.travel_explore,
                          '资源嗅探',
                          () {
                            Navigator.pop(sheetContext);
                            _openSniffer();
                          },
                          enabled: notHome,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.lightbulb_outline,
                          '屏幕常亮',
                          () {
                            Navigator.pop(sheetContext);
                            settings.setKeepScreenOn(!settings.keepScreenOn);
                          },
                          highlighted: settings.keepScreenOn,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.bedtime_outlined,
                          '护眼模式',
                          () {
                            Navigator.pop(sheetContext);
                            settings.setEyeCare(!settings.eyeCare);
                          },
                          highlighted: settings.eyeCare,
                        ),
                        _menuItem(sheetContext, Icons.download_outlined,
                            '下载管理', () {
                          Navigator.pop(sheetContext);
                          _openDownloads();
                        }),
                        _menuItem(
                          sheetContext,
                          Icons.image_outlined,
                          '无图模式',
                          () {
                            Navigator.pop(sheetContext);
                            settings.setNoImage(!settings.noImage);
                          },
                          highlighted: settings.noImage,
                        ),
                        _menuItem(
                          sheetContext,
                          Icons.block_outlined,
                          '广告拦截',
                          () {
                            Navigator.pop(sheetContext);
                            settings.setAdBlock(!settings.adBlock);
                          },
                          highlighted: settings.adBlock,
                        ),
                        _menuItem(
                            sheetContext, Icons.settings_outlined, '设置', () {
                          Navigator.pop(sheetContext);
                          _openSettings();
                        }),
                        _menuItem(sheetContext, Icons.refresh, '刷新', () {
                          Navigator.pop(sheetContext);
                          _currentTab.controller.reload();
                        }),
                        _menuItem(sheetContext, Icons.exit_to_app, '退出', () {
                          Navigator.pop(sheetContext);
                          SystemNavigator.pop();
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool enabled = true,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.disabledColor
        : highlighted
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _currentTab.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制网址')),
    );
  }

  Future<void> _toggleDesktopMode() async {
    final tab = _currentTab;
    tab.desktopMode = !tab.desktopMode;
    await tab.controller.setUserAgent(_effectiveUA(tab));
    tab.controller.reload();
    setState(() {});
  }

  // ---- 生命周期 ----

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistOpenTabs();
      if (SettingsService.instance.clearOnExit) {
        _clearOnExit();
      }
    }
  }

  void _persistOpenTabs() {
    final service = BrowserDataService.instance;
    if (!SettingsService.instance.restoreTabs) {
      service.clearOpenTabs();
      return;
    }
    final tabs = _tabs
        .where((t) => !t.isHome && !t.incognito && t.url.isNotEmpty)
        .map((t) => {'url': t.url, 'title': t.title})
        .toList();
    service.saveOpenTabs(tabs);
  }

  Future<void> _clearOnExit() async {
    await BrowserDataService.instance.clearHistory();
    for (final tab in _tabs) {
      try {
        await tab.controller.clearCache();
        await tab.controller.clearLocalStorage();
      } catch (_) {}
    }
  }

  // ---- 系统返回键 ----

  Future<bool> _onWillPop() async {
    // 地址栏处于编辑态（建议面板/软键盘）时返回键优先收起而非导航，
    // 与主流浏览器一致；平台视图触摸不透传焦点，用户需要这条确定退出路径
    if (_urlFocusNode.hasFocus || _suggestionOpen) {
      _collapseUrlBar();
      return false;
    }
    final tab = _currentTab;
    if (!tab.isHome) {
      if (_canGoBack) {
        tab.controller.goBack();
        return false;
      }
      setState(() => tab.isHome = true);
      return false;
    }
    return true;
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (_appReady && !_currentTab.isHome) _buildTopBar(),
              if (_appReady && !_currentTab.isHome && _finding)
                _buildFindBar(),
              if (_appReady && !_currentTab.isHome)
                _currentTab.isLoading
                    ? LinearProgressIndicator(
                        value: _currentTab.progress / 100,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                      )
                    : const SizedBox(height: 2),
              if (_appReady &&
                  !_currentTab.isHome &&
                  SettingsService.instance.tabBarEnabled)
                _buildTabBar(),
              if (_appReady &&
                  !_currentTab.isHome &&
                  _suggestionOpen)
                _buildSuggestionPanel(),
              Expanded(
                child: !_appReady
                    // 初始化期间显示加载占位，避免白屏
                    ? const Center(child: CircularProgressIndicator())
                    : (_currentTab.isHome
                        ? HomePage(
                            key: _homeKey,
                            onSearch: _openUrl,
                            onOpenUrl: _openUrl,
                            onOpenSettings: _openSettings,
                            onOpenDownloads: _openDownloads,
                            onClearHistory: _reloadHome,
                          )
                        : _buildWebViewStack()),
              ),
              if (_appReady) _buildBottomToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  void _reloadHome() {
    _homeKey.currentState?.reload();
  }

  // ---- 搜索工具栏（Via：启用搜索工具栏） ----

  // ---- 标签栏 ----

  Widget _buildTabBar() {
    final theme = Theme.of(context);
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final selected = index == _currentIndex;
                final title = tab.title.isEmpty ? '新标签页' : tab.title;
                return GestureDetector(
                  onTap: () => _switchTab(index),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 140),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.incognito) ...[
                          Icon(Icons.visibility_off_outlined,
                              size: 13, color: theme.colorScheme.outline),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _closeTab(index),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: '新建标签页',
            visualDensity: VisualDensity.compact,
            onPressed: () => _addTab(),
          ),
        ],
      ),
    );
  }

  // ---- 地址栏建议 ----

  Timer? _suggestionDebounce;
  Timer? _suggestionHideTimer;

  void _onUrlFocusChanged() {
    if (!mounted) return;
    final settings = SettingsService.instance;
    final anySource = settings.suggestFromSearchEngine ||
        settings.suggestFromHistory ||
        settings.suggestFromBookmarks;
    if (_urlFocusNode.hasFocus) {
      _suggestionHideTimer?.cancel();
      if (!anySource) return;
      _refreshSuggestions(_urlController.text);
    } else {
      _suggestionDebounce?.cancel();
      _suggestionHideTimer?.cancel();
      _suggestionHideTimer = Timer(
        const Duration(milliseconds: 250),
        _hideSuggestions,
      );
    }
  }

  void _onUrlChanged(String value) {
    setState(() {});
    if (!_urlFocusNode.hasFocus) return;
    final settings = SettingsService.instance;
    final anySource = settings.suggestFromSearchEngine ||
        settings.suggestFromHistory ||
        settings.suggestFromBookmarks;
    if (!anySource) return;
    _suggestionDebounce?.cancel();
    _suggestionDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _refreshSuggestions(value),
    );
  }

  void _hideSuggestions() {
    _suggestionRequestId++;
    _suggestionDebounce?.cancel();
    _suggestionHideTimer?.cancel();
    if (!_suggestionOpen && !_suggestionLoading) return;
    setState(() {
      _suggestionOpen = false;
      _suggestionLoading = false;
      _suggestions.clear();
    });
  }

  /// 收起地址栏瞬时状态：清除焦点（收起软键盘）并立即关闭建议面板。
  ///
  /// 背景：Android 平台视图（WebView）自行消费触摸，不会透传给 Flutter 焦点系统，
  /// 用户与网页交互（滑动 / 点链接 / 点工具栏）时地址栏仍停留在编辑态，
  /// 建议面板与软键盘常驻会持续压缩 WebView 可视区（表现为"页面滑不了"）。
  /// 凡可感知到的"用户回到网页"信号（滚动、导航开始、工具栏、返回键）都应主动收起。
  void _collapseUrlBar() {
    if (!mounted) return;
    _suggestionHideTimer?.cancel();
    if (_urlFocusNode.hasFocus) _urlFocusNode.unfocus();
    _hideSuggestions();
  }

  static bool _suggestMatches(String candidate, String query) {
    if (query.isEmpty) return true;
    return candidate.toLowerCase().contains(query.toLowerCase());
  }

  Future<void> _refreshSuggestions(String query) async {
    final settings = SettingsService.instance;
    final text = query.trim();
    final results = <String>[];
    final seen = <String>{};
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || !seen.add(t)) return;
      results.add(t);
    }

    if (settings.suggestFromHistory) {
      if (settings.searchHistoryEnabled) {
        final searchHistory =
            await BrowserDataService.instance.searchHistory();
        for (final q in searchHistory) {
          if (_suggestMatches(q, text)) add(q);
        }
      }
      final entries = await BrowserDataService.instance.history();
      for (final e in entries) {
        if (_suggestMatches(e.title, text) || _suggestMatches(e.url, text)) {
          add(e.title.isNotEmpty ? e.title : e.url);
        }
      }
    }
    if (settings.suggestFromBookmarks) {
      final bookmarks = await BrowserDataService.instance.bookmarks();
      for (final b in bookmarks) {
        if (_suggestMatches(b.name, text) || _suggestMatches(b.url, text)) {
          add(b.name.isNotEmpty ? b.name : b.url);
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _suggestions
        ..clear()
        ..addAll(results.take(8));
      _suggestionOpen = true;
      _suggestionLoading = settings.searchSuggestions &&
          settings.suggestFromSearchEngine &&
          text.isNotEmpty;
    });
    if (settings.searchSuggestions &&
        settings.suggestFromSearchEngine &&
        text.isNotEmpty) {
      final requestId = ++_suggestionRequestId;
      final online = await _fetchOnlineSuggestions(text);
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() {
        _suggestionLoading = false;
        for (final s in online) {
          if (_suggestions.length >= 12) break;
          if (!_suggestions.contains(s)) _suggestions.add(s);
        }
      });
    }
  }

  /// 在线搜索建议：百度 sugrec / 必应 osjson / Google firefox 客户端
  Future<List<String>> _fetchOnlineSuggestions(String query) async {
    final engineKey = SettingsService.instance.searchEngine;
    final encoded = Uri.encodeComponent(query);
    final url = switch (engineKey) {
      'bing' => 'https://api.bing.com/osjson.aspx?query=$encoded',
      'google' => 'https://www.google.com/complete/search?client=firefox&q=$encoded',
      _ => 'https://www.baidu.com/sugrec?prod=pc&wd=$encoded',
    };
    try {
      final response = await http
          .get(Uri.parse(url), headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          })
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return const [];
      final body = response.body;
      if (engineKey == 'bing' || engineKey == 'google') {
        final decoded = jsonDecode(body);
        if (decoded is List && decoded.length >= 2 && decoded[1] is List) {
          return (decoded[1] as List).whereType<String>().toList();
        }
        return const [];
      }
      // 百度 sugrec：{"g":[{"q":"..."}]} 或 {"s":["..."]}
      final gMatch =
          RegExp(r'"g"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
      if (gMatch != null) {
        return RegExp(r'"q"\s*:\s*"((?:[^"\\]|\\.)*)"')
            .allMatches(gMatch.group(1)!)
            .map((e) => e.group(1)!)
            .toList();
      }
      final sMatch =
          RegExp(r'"s"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(body);
      if (sMatch != null) {
        return RegExp(r'"((?:[^"\\]|\\.)*)"')
            .allMatches(sMatch.group(1)!)
            .map((e) => e.group(1)!)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  void _applySuggestion(String text) {
    _suggestionHideTimer?.cancel();
    _hideSuggestions();
    _urlController.text = text;
    _urlController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
    _submitInput(text);
  }

  Widget _buildSuggestionPanel() {
    final theme = Theme.of(context);
    final count = _suggestions.length + (_suggestionLoading ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return Material(
      key: suggestionPanelKey,
      elevation: 2,
      color: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: count,
          itemBuilder: (context, index) {
            if (_suggestionLoading && index == count - 1) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final text = _suggestions[index];
            return ListTile(
              dense: true,
              leading: Icon(
                _currentTab.url.isNotEmpty &&
                        _suggestMatches(_currentTab.url, text)
                    ? Icons.history
                    : Icons.search,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _applySuggestion(text),
            );
          },
        ),
      ),
    );
  }
  Widget _buildFindBar() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _findController,
                  autofocus: true,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: '页内查找',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onChanged: _onFindChanged,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(_findCount, style: theme.textTheme.bodySmall),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              tooltip: '上一个',
              visualDensity: VisualDensity.compact,
              onPressed: _findPrev,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              tooltip: '下一个',
              visualDensity: VisualDensity.compact,
              onPressed: _findNext,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭查找',
              visualDensity: VisualDensity.compact,
              onPressed: _stopFind,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final theme = Theme.of(context);
    final tab = _currentTab;
    final secure = tab.url.startsWith('https://');
    return Material(
      elevation: 1,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: TextField(
                  controller: _urlController,
                  focusNode: _urlFocusNode,
                  style: theme.textTheme.bodyMedium,
                  textInputAction: TextInputAction.go,
                  keyboardType: TextInputType.url,
                  onTap: () {
                    _urlController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _urlController.text.length,
                    );
                  },
                  onSubmitted: _onUrlSubmitted,
                  onChanged: _onUrlChanged,
                  decoration: InputDecoration(
                    hintText: '搜索或输入网址',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    prefixIcon: Icon(
                      secure ? Icons.lock_outline : Icons.public_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    suffixIcon: _urlController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              _urlController.clear();
                              _urlFocusNode.requestFocus();
                            },
                          )
                        : null,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(tab.isLoading ? Icons.close : Icons.refresh),
              tooltip: tab.isLoading ? '停止' : '刷新',
              onPressed: () {
                _collapseUrlBar();
                if (tab.isLoading) {
                  tab.controller.loadRequest(Uri.parse('about:blank'));
                } else {
                  tab.controller.reload();
                }
              },
            ),
            PopupMenuButton<String>(
              tooltip: '菜单',
              onSelected: (value) {
                _collapseUrlBar();
                switch (value) {
                  case 'forward':
                    _currentTab.controller.goForward();
                    break;
                  case 'downloads':
                    _openDownloads();
                    break;
                  case 'settings':
                    _openSettings();
                    break;
                  case 'menu':
                    _showMainMenu();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'forward',
                  enabled: _canGoForward,
                  child: const ListTile(
                    leading: Icon(Icons.arrow_forward),
                    title: Text('前进'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'downloads',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('下载管理'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('设置'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'menu',
                  child: ListTile(
                    leading: Icon(Icons.grid_view_outlined),
                    title: Text('功能菜单'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewStack() {
    final stack = IndexedStack(
      index: _currentIndex,
      children: _tabs.map((tab) {
        return WebViewWidget(controller: tab.controller);
      }).toList(),
    );
    if (!SettingsService.instance.gestureSwitchTab) return stack;
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      onHorizontalDragStart: (details) {
        _edgeDragStartX = details.localPosition.dx;
      },
      onHorizontalDragEnd: (details) {
        final startX = _edgeDragStartX;
        _edgeDragStartX = null;
        if (startX == null) return;
        final velocity = details.primaryVelocity ?? 0;
        const edge = 32;
        const threshold = 300; // px/s
        if (startX < edge && velocity > threshold) {
          _switchTabByGesture(-1);
        } else if (startX > width - edge && velocity < -threshold) {
          _switchTabByGesture(1);
        }
      },
      child: stack,
    );
  }

  void _switchTabByGesture(int delta) {
    final next = _currentIndex + delta;
    if (next < 0 || next >= _tabs.length) return;
    _switchTab(next);
  }

  Widget _buildBottomToolbar() {
    final theme = Theme.of(context);
    final tab = _currentTab;
    return Material(
      elevation: 3,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: _toolbarButton(
                  theme,
                  icon: Icons.arrow_back,
                  label: '后退',
                  enabled: _canGoBack,
                  onTap: () => tab.controller.goBack(),
                ),
              ),
              Expanded(
                child: _toolbarButton(
                  theme,
                  icon: tab.isHome ? Icons.home : Icons.home_outlined,
                  label: '主页',
                  onTap: _goHome,
                ),
              ),
              Expanded(
                child: _toolbarButton(
                  theme,
                  icon: Icons.crop_square,
                  label: '多窗口',
                  badge: '${_tabs.length}',
                  onTap: _openTabsPage,
                ),
              ),
              Expanded(
                child: _toolbarButton(
                  theme,
                  icon: Icons.more_horiz,
                  label: '菜单',
                  onTap: _showMainMenu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    String? badge,
  }) {
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withAlpha(89);
    return InkWell(
      onTap: enabled
          ? () {
              // 点击工具栏即视为离开地址栏编辑态：收起面板与软键盘，
              // 恢复 WebView 可视区（否则编辑态常驻会压缩页面）
              _collapseUrlBar();
              onTap();
            }
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badge != null,
            label: badge == null ? null : Text(badge),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
