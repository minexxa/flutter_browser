import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/browser_tab.dart';
import '../models/quick_link.dart';
import '../pages/downloads_page.dart';
import '../pages/home_page.dart';
import '../pages/settings_page.dart';
import '../pages/tabs_page.dart';
import '../services/browser_data_service.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';
import '../utils/js_injections.dart';
import '../utils/url_utils.dart';
import '../utils/webview_ext.dart';

/// 主界面：首页 / 网页浏览 切换 + 多标签 + 底部工具栏
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  static const String _volumeChannelName =
      'com.example.flutter_android_browser/volume';

  final List<BrowserTab> _tabs = [];
  int _currentIndex = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final MethodChannel _volumeChannel = const MethodChannel(_volumeChannelName);

  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _appReady = false;

  BrowserTab get _currentTab => _tabs[_currentIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SettingsService.instance.addListener(_onSettingsChanged);
    _initApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsService.instance.removeListener(_onSettingsChanged);
    _volumeChannel.setMethodCallHandler(null);
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    await SettingsService.instance.load();
    await DownloadService.instance.init();
    _setupVolumeChannel();

    final settings = SettingsService.instance;
    if (settings.restoreTabs) {
      final saved = await BrowserDataService.instance.loadOpenTabs();
      for (final item in saved) {
        if (!mounted) return;
        final url = item['url'] ?? '';
        if (url.isNotEmpty) {
          await _addTab(url: url, title: item['title'] ?? '新标签页');
        }
      }
    }
    if (_tabs.isEmpty) {
      if (!mounted) return;
      await _addTab();
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
  }

  void _applyFullscreen() {
    if (SettingsService.instance.fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ---- 标签管理 ----

  Future<void> _addTab({String url = '', String title = '新标签页'}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final tab = BrowserTab(
      id: id,
      controller: WebViewController(),
      isHome: url.isEmpty,
      title: title,
      url: url,
    );

    final settings = SettingsService.instance;
    final backgroundColor = mounted
        ? Theme.of(context).colorScheme.surface
        : const Color(0xFFFFFFFF);
    tab.controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(backgroundColor)
      ..setNavigationDelegate(_buildNavigationDelegate(tab));

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
    await tab.controller.setUserAgent(_effectiveUA(tab));
    applyFontSize(tab.controller, settings.fontSize.textZoom);
    applyForceZoom(tab.controller, settings.forceZoom);
    applyMediaGesture(tab.controller, settings.saveData);
    applyGeolocationEnabled(tab.controller, settings.geolocationAccess);

    _tabs.add(tab);
    _currentIndex = _tabs.length - 1;
    if (url.isNotEmpty) {
      await tab.controller.loadRequest(Uri.parse(url));
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
        setState(() {
          tab.url = url;
          tab.isLoading = true;
          tab.isHome = false;
          if (!_urlFocusNode.hasFocus) {
            _urlController.text = url;
          }
        });
      },
      onPageFinished: (String url) async {
        if (!mounted) return;
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
            _urlController.text = url;
          }
        });
        BrowserDataService.instance.addHistory(url, title);
        await _injectScripts(tab);
        await _fillSavedPassword(tab);
        _updateNavState();
      },
      onWebResourceError: (WebResourceError error) {
        debugPrint('WebView 错误: ${error.description}');
      },
      onNavigationRequest: (NavigationRequest request) {
        if (request.isMainFrame) {
          if (SettingsService.instance.adBlock && _isAdHost(request.url)) {
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
    if (tab.desktopMode) return BrowserIdentity.byKey('pc').userAgent;
    return SettingsService.instance.effectiveUserAgent;
  }

  bool _isAdHost(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    for (final ad in _adHosts) {
      if (host == ad || host.endsWith('.$ad')) return true;
    }
    return false;
  }

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
      BrowserDataService.instance.savePassword(host, username, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已保存')),
      );
    } catch (_) {}
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

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      final tab = _tabs[0];
      tab.isHome = true;
      tab.title = '新标签页';
      tab.url = '';
      tab.progress = 0;
      tab.isLoading = false;
      tab.controller.loadRequest(Uri.parse('about:blank'));
      setState(() {});
      return;
    }
    _tabs.removeAt(index);
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
        _urlController.text = _currentTab.url;
      }
    });
    _updateNavState();
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

  void _openUrl(String input) {
    final url = normalizeInput(
      input,
      engine: SettingsService.instance.effectiveSearchEngine,
    );
    if (url.isEmpty) return;
    _urlFocusNode.unfocus();
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
          onCloseAll: () {
            Navigator.pop(context);
            setState(() {
              _tabs.clear();
            });
            _addTab();
          },
        ),
      ),
    );
  }

  // ---- 菜单 ----

  void _showMainMenu() {
    final settings = SettingsService.instance;
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
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  children: [
                    _menuItem(sheetContext, Icons.add, '新建标签页', () {
                      Navigator.pop(sheetContext);
                      _addTab();
                    }),
                    _menuItem(sheetContext, Icons.star_outline, '添加收藏', () {
                      Navigator.pop(sheetContext);
                      _addCurrentToHome();
                    }),
                    _menuItem(sheetContext, Icons.share_outlined, '分享', () {
                      Navigator.pop(sheetContext);
                      _sharePage();
                    }),
                    _menuItem(sheetContext, Icons.copy_outlined, '复制网址', () {
                      Navigator.pop(sheetContext);
                      _copyUrl();
                    }),
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
                      highlighted: _currentTab.desktopMode,
                    ),
                    _menuItem(sheetContext, Icons.download_outlined, '下载管理', () {
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
                    _menuItem(sheetContext, Icons.settings_outlined, '设置', () {
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

  Future<void> _addCurrentToHome() async {
    final tab = _currentTab;
    if (tab.isHome || tab.url.isEmpty) return;
    await BrowserDataService.instance.addQuickLink(
      QuickLink(
        id: 'ql_${DateTime.now().millisecondsSinceEpoch}',
        name: tab.title,
        url: tab.url,
      ),
    );
    if (!mounted) return;
    _homeKey.currentState?.reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到主页收藏')),
    );
  }

  void _sharePage() {
    Clipboard.setData(ClipboardData(text: _currentTab.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制链接到剪贴板')),
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
        .where((t) => !t.isHome && t.url.isNotEmpty)
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
              if (_appReady && !_currentTab.isHome)
                _currentTab.isLoading
                    ? LinearProgressIndicator(
                        value: _currentTab.progress / 100,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                      )
                    : const SizedBox(height: 2),
              Expanded(
                child: _appReady
                    ? (_currentTab.isHome
                        ? HomePage(
                            key: _homeKey,
                            onSearch: _openUrl,
                            onOpenUrl: _openUrl,
                            onOpenSettings: _openSettings,
                            onOpenDownloads: _openDownloads,
                            onClearHistory: _reloadHome,
                          )
                        : _buildWebViewStack())
                    : const SizedBox.shrink(),
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
                  onChanged: (_) => setState(() {}),
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
    return IndexedStack(
      index: _currentIndex,
      children: _tabs.map((tab) {
        return WebViewWidget(controller: tab.controller);
      }).toList(),
    );
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
      onTap: enabled ? onTap : null,
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

/// 内建广告域名黑名单（主框架导航级别拦截）
const List<String> _adHosts = [
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.com',
  'admob.com',
  'adsmogo.com',
  'admarvel.com',
  'inmobi.com',
  'applovin.com',
  'unityads.unity3d.com',
  'vungle.com',
  'chartboost.com',
  'tapjoy.com',
  'mopub.com',
  'adcolony.com',
  'pos.baidu.com',
  'cbjs.baidu.com',
  'cpro.baidu.com',
  'union.baidu.com',
  'entry.baidu.com',
  'poscdn.baidu.com',
  'soflop.cn',
  '51yes.com',
  'admaster.com.cn',
  'allyes.com',
  'adchina.com',
  'adsky.cn',
];
