import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_settings.dart';
import '../utils/url_utils.dart';

/// 网站设置服务：按 host 持久化站点覆盖项
class SiteSettingsService extends ChangeNotifier {
  SiteSettingsService._();

  static final SiteSettingsService instance = SiteSettingsService._();

  static const String _prefsKey = 'site_settings_v1';

  final Map<String, SiteSettings> _sites = {};
  bool _loaded = false;

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((host, value) {
          _sites[host] =
              SiteSettings.fromJson(value as Map<String, dynamic>);
        });
      } catch (_) {
        _sites.clear();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    _sites.forEach((host, settings) => map[host] = settings.toJson());
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  SiteSettings? ofHost(String host) => _sites[host];

  /// 取可编辑副本；无设置则新建空设置
  SiteSettings editableFor(String host) =>
      _sites[host] ?? SiteSettings(host: host);

  Future<void> save(SiteSettings settings) async {
    if (settings.isEmpty) {
      _sites.remove(settings.host);
    } else {
      _sites[settings.host] = settings;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String host) async {
    _sites.remove(host);
    await _persist();
    notifyListeners();
  }

  // ---- 便捷判定 ----

  static String hostOf(String url) =>
      Uri.tryParse(url)?.host.toLowerCase() ?? '';

  /// 站点是否阻止图片（无设置=允许）
  bool imagesBlocked(String host) => _sites[host]?.images == false;

  /// 站点广告拦截是否生效（无设置=跟随全局）
  bool adBlockEnabled(String host, bool globalEnabled) =>
      _sites[host]?.adBlock ?? globalEnabled;

  /// 站点 JS 是否启用（无设置=开）
  bool javaScriptEnabled(String host) => _sites[host]?.javaScript ?? true;

  /// 站点 Cookie 是否允许（无设置=允许）
  bool cookiesEnabled(String host) => _sites[host]?.cookies ?? true;

  /// 站点覆盖的 UA；null 表示无站点覆盖（跟随全局/标签桌面版）
  String? userAgentOverride(String host) {
    final ua = _sites[host]?.userAgent;
    if (ua == null) return null;
    if (ua == 'desktop') return BrowserIdentity.byKey('pc').userAgent;
    if (ua == 'mobile') return null; // 移动版 = 跟随全局 UA
    return ua.isEmpty ? null : ua;
  }
}
