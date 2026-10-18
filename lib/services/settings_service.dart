import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/url_utils.dart';

/// 主题模式
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromString(String? value) => switch (value) {
        'light' => AppThemeMode.light,
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.system,
      };
}

/// 字体大小档位（对应 Via 的最小/较小/标准/较大/最大）
enum FontSizeLevel {
  smallest('最小', 75),
  smaller('较小', 90),
  standard('标准', 100),
  larger('较大', 120),
  largest('最大', 150);

  const FontSizeLevel(this.label, this.textZoom);

  final String label;
  final int textZoom;

  static FontSizeLevel fromIndex(int index) =>
      values[index.clamp(0, values.length - 1)];
}

/// 设置服务：加载 / 持久化 / 变更通知
class SettingsService extends ChangeNotifier {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const String _prefsKey = 'browser_settings_v1';

  final Map<String, dynamic> _values = {
    'searchEngine': 'baidu',
    'customSearchUrl': '',
    'searchQuickWords': <String, String>{},
    'searchSuggestions': true,
    'suggestFromSearchEngine': true,
    'suggestFromHistory': true,
    'suggestFromBookmarks': true,
    'searchHistoryEnabled': true,
    'searchBoxStyle': 'line',
    'searchBoxBlur': false,
    'addressBarContent': 'url',
    'searchToolbar': false,
    'tabBarEnabled': false,
    'cookieAccept': true,
    'browserIdentity': 'android',
    'customUserAgent': '',
    'fontSizeLevel': 2,
    'homePage': 'default',
    'startPage': 'restore',
    'startPageUrl': '',
    'restoreTabs': true,
    'volumeKeyScroll': false,
    'themeMode': 'system',
    'themeColor': 0xFF1A73E8,
    'forceZoom': false,
    'fullscreen': false,
    'eyeCare': false,
    'keepScreenOn': false,
    'gestureSwitchTab': true,
    'adBlock': true,
    'noImage': false,
    'saveData': false,
    'savePassword': true,
    'clipboardAccess': false,
    'geolocationAccess': false,
    'clearOnExit': false,
    'downloadPath': 'default',
  };

  bool _loaded = false;

  // ---- 读取 ----

  String get searchEngine => _values['searchEngine'] as String;
  String get customSearchUrl => _values['customSearchUrl'] as String;

  /// 搜索引擎快捷词：engineKey -> 快捷词（如 g -> google）
  Map<String, String> get searchQuickWords {
    final raw = _values['searchQuickWords'];
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return const {};
  }

  bool get searchSuggestions => _values['searchSuggestions'] as bool;
  bool get suggestFromSearchEngine => _values['suggestFromSearchEngine'] as bool;
  bool get suggestFromHistory => _values['suggestFromHistory'] as bool;
  bool get suggestFromBookmarks => _values['suggestFromBookmarks'] as bool;
  bool get searchHistoryEnabled => _values['searchHistoryEnabled'] as bool;

  /// 搜索框样式：'line' 线条 / 'rect' 矩形
  String get searchBoxStyle => _values['searchBoxStyle'] as String;

  /// 搜索框模糊效果
  bool get searchBoxBlur => _values['searchBoxBlur'] as bool;

  /// 地址栏内容：'url' 网址 / 'domain' 域名 / 'title' 标题
  String get addressBarContent => _values['addressBarContent'] as String;
  /// 搜索工具栏：在搜索结果页底部显示引擎快捷切换栏
  bool get searchToolbar => _values['searchToolbar'] as bool;
  bool get tabBarEnabled => _values['tabBarEnabled'] as bool;
  bool get cookieAccept => _values['cookieAccept'] as bool;
  String get browserIdentity => _values['browserIdentity'] as String;
  String get customUserAgent => _values['customUserAgent'] as String;
  int get fontSizeLevel => _values['fontSizeLevel'] as int;
  String get homePage => _values['homePage'] as String;
  String get startPage => _values['startPage'] as String;
  String get startPageUrl => _values['startPageUrl'] as String;
  bool get restoreTabs => _values['restoreTabs'] as bool;
  bool get volumeKeyScroll => _values['volumeKeyScroll'] as bool;
  AppThemeMode get themeMode => AppThemeMode.fromString(_values['themeMode'] as String?);
  int get themeColor => (_values['themeColor'] as num?)?.toInt() ?? 0xFF1A73E8;
  bool get forceZoom => _values['forceZoom'] as bool;
  bool get fullscreen => _values['fullscreen'] as bool;
  bool get eyeCare => _values['eyeCare'] as bool;
  bool get keepScreenOn => _values['keepScreenOn'] as bool;
  bool get gestureSwitchTab => _values['gestureSwitchTab'] as bool;
  bool get adBlock => _values['adBlock'] as bool;
  bool get noImage => _values['noImage'] as bool;
  bool get saveData => _values['saveData'] as bool;
  bool get savePassword => _values['savePassword'] as bool;
  bool get clipboardAccess => _values['clipboardAccess'] as bool;
  bool get geolocationAccess => _values['geolocationAccess'] as bool;
  bool get clearOnExit => _values['clearOnExit'] as bool;
  String get downloadPath => _values['downloadPath'] as String;

  FontSizeLevel get fontSize => FontSizeLevel.fromIndex(fontSizeLevel);

  // ---- 加载 / 保存 ----

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _values.addAll(decoded);
        }
      } catch (_) {
        // 配置损坏时保留默认值
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_values));
  }

  void _set(String key, Object? value) {
    _values[key] = value;
    notifyListeners();
    _persist();
  }

  // ---- 更新 ----

  void setSearchEngine(String key, {String customUrl = ''}) {
    _values['searchEngine'] = key;
    _values['customSearchUrl'] = customUrl;
    notifyListeners();
    _persist();
  }

  /// 设置某引擎的快捷词；空串或 null 表示移除
  void setSearchQuickWord(String engineKey, String? word) {
    final words = Map<String, String>.from(searchQuickWords);
    final trimmed = word?.trim() ?? '';
    if (trimmed.isEmpty) {
      words.remove(engineKey);
    } else {
      words[engineKey] = trimmed;
    }
    _set('searchQuickWords', words);
  }

  void setBrowserIdentity(String key, {String customUA = ''}) {
    _values['browserIdentity'] = key;
    _values['customUserAgent'] = customUA;
    notifyListeners();
    _persist();
  }

  void setFontSizeLevel(int level) =>
      _set('fontSizeLevel', level.clamp(0, FontSizeLevel.values.length - 1));

  void setHomePage(String value) => _set('homePage', value);
  void setStartPage(String value) => _set('startPage', value);
  void setStartPageUrl(String value) => _set('startPageUrl', value);
  void setRestoreTabs(bool value) => _set('restoreTabs', value);
  void setVolumeKeyScroll(bool value) => _set('volumeKeyScroll', value);
  void setThemeMode(AppThemeMode mode) => _set('themeMode', mode.name);
  void setThemeColor(int color) => _set('themeColor', color);
  void setForceZoom(bool value) => _set('forceZoom', value);
  void setFullscreen(bool value) => _set('fullscreen', value);
  void setEyeCare(bool value) => _set('eyeCare', value);
  void setKeepScreenOn(bool value) => _set('keepScreenOn', value);
  void setGestureSwitchTab(bool value) => _set('gestureSwitchTab', value);
  void setAdBlock(bool value) => _set('adBlock', value);
  void setSearchSuggestions(bool value) => _set('searchSuggestions', value);
  void setSuggestFromSearchEngine(bool value) =>
      _set('suggestFromSearchEngine', value);
  void setSuggestFromHistory(bool value) => _set('suggestFromHistory', value);
  void setSuggestFromBookmarks(bool value) =>
      _set('suggestFromBookmarks', value);
  void setSearchHistoryEnabled(bool value) =>
      _set('searchHistoryEnabled', value);
  void setSearchBoxStyle(String value) => _set('searchBoxStyle', value);
  void setSearchBoxBlur(bool value) => _set('searchBoxBlur', value);
  void setAddressBarContent(String value) => _set('addressBarContent', value);
  void setSearchToolbar(bool value) => _set('searchToolbar', value);
  void setTabBarEnabled(bool value) => _set('tabBarEnabled', value);
  void setCookieAccept(bool value) => _set('cookieAccept', value);
  void setNoImage(bool value) => _set('noImage', value);
  void setSaveData(bool value) => _set('saveData', value);
  void setSavePassword(bool value) => _set('savePassword', value);
  void setClipboardAccess(bool value) => _set('clipboardAccess', value);
  void setGeolocationAccess(bool value) => _set('geolocationAccess', value);
  void setClearOnExit(bool value) => _set('clearOnExit', value);
  void setDownloadPath(String value) => _set('downloadPath', value);

  // ---- 派生值 ----

  /// 生效的 User-Agent（null = 系统默认）
  String? get effectiveUserAgent {
    if (browserIdentity == 'custom') {
      return customUserAgent.isEmpty ? null : customUserAgent;
    }
    return BrowserIdentity.byKey(browserIdentity).userAgent;
  }

  /// 生效的搜索引擎
  SearchEngine get effectiveSearchEngine {
    if (searchEngine == 'custom' && customSearchUrl.isNotEmpty) {
      return SearchEngine('custom', '自定义', customSearchUrl);
    }
    return SearchEngine.byKey(searchEngine);
  }
}
