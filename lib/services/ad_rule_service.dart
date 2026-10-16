import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ad_subscription.dart';

/// 内建广告域名黑名单（与 Via「内建规则仅拦截常见广告」对齐）
const List<String> builtinAdHosts = [
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

/// 广告拦截规则订阅服务：订阅管理 / 规则下载 / 本地缓存 / 域名匹配
class AdRuleService extends ChangeNotifier {
  AdRuleService._();

  static final AdRuleService instance = AdRuleService._();

  static const String _subsKey = 'ad_subscriptions_v1';
  static const Duration _timeout = Duration(seconds: 20);
  static final RegExp _hostsLineRe =
      RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}\s+(\S+)$');
  static final RegExp _domainRe = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$',
  );

  List<AdSubscription> _subs = [];
  bool _loaded = false;
  bool _updating = false;
  final Set<String> _domains = {};

  List<AdSubscription> get subscriptions => List.unmodifiable(_subs);
  bool get updating => _updating;
  int get ruleCount => _domains.length;

  /// 加载订阅列表并读入本地缓存域名
  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_subsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _subs = list
            .map((e) => AdSubscription.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _subs = [];
      }
    }
    await _reloadDomains();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persistSubs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _subsKey,
      jsonEncode(_subs.map((e) => e.toJson()).toList()),
    );
  }

  Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/ad_rules');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _cacheFile(String id) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$id.txt');
  }

  /// 从缓存文件重建内存域名集合（内建域名 + 全部已启用订阅）
  Future<void> _reloadDomains() async {
    final domains = <String>{...builtinAdHosts};
    for (final sub in _subs) {
      if (!sub.enabled) continue;
      final file = await _cacheFile(sub.id);
      if (!file.existsSync()) continue;
      try {
        for (final line in await file.readAsLines()) {
          final d = line.trim();
          if (d.isNotEmpty) domains.add(d);
        }
      } catch (_) {
        // 单个缓存读取失败不影响其余规则
      }
    }
    _domains
      ..clear()
      ..addAll(domains);
  }

  // ---- 订阅管理 ----

  /// 添加订阅并立即更新规则；下载失败时 fail-fast（不保留空订阅）
  Future<void> addSubscription(String name, String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw '订阅地址不能为空';
    final id = 'sub_${DateTime.now().millisecondsSinceEpoch}';
    final sub = AdSubscription(
      id: id,
      name: name.trim().isEmpty ? Uri.parse(trimmed).host : name.trim(),
      url: trimmed,
    );
    _subs.insert(0, sub);
    await _persistSubs();
    notifyListeners();
    try {
      await _downloadAndCache(sub);
    } catch (_) {
      _subs.removeWhere((e) => e.id == id);
      await _persistSubs();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeSubscription(String id) async {
    _subs.removeWhere((e) => e.id == id);
    await _persistSubs();
    final file = await _cacheFile(id);
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await _reloadDomains();
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final sub = _subs.firstWhere((e) => e.id == id);
    sub.enabled = enabled;
    await _persistSubs();
    await _reloadDomains();
    notifyListeners();
  }

  /// 更新单个订阅；失败时保留旧缓存并抛出错误信息
  Future<void> updateSubscription(String id) async {
    final sub = _subs.firstWhere((e) => e.id == id);
    await _downloadAndCache(sub);
  }

  /// 更新全部订阅；全部失败时抛出最后一次错误信息
  Future<void> updateAll() async {
    _updating = true;
    notifyListeners();
    Object? lastError;
    try {
      for (final sub in List.of(_subs)) {
        try {
          await _downloadAndCache(sub);
        } catch (e) {
          lastError = e;
        }
      }
    } finally {
      _updating = false;
      notifyListeners();
    }
    if (lastError != null) throw lastError;
  }

  Future<void> _downloadAndCache(AdSubscription sub) async {
    final response = await http.get(Uri.parse(sub.url)).timeout(_timeout);
    if (response.statusCode != 200) {
      throw '下载失败：HTTP ${response.statusCode}';
    }
    final domains = parseRules(response.body);
    if (domains.isEmpty) throw '规则文件为空或无法解析';
    final file = await _cacheFile(sub.id);
    await file.writeAsString(domains.join('\n'));
    sub.lastUpdated = DateTime.now().millisecondsSinceEpoch;
    sub.ruleCount = domains.length;
    await _persistSubs();
    await _reloadDomains();
    notifyListeners();
  }

  // ---- 匹配 ----

  /// 判断 URL 主机是否命中广告域名（内建 + 已启用订阅，含子域）
  bool isAdHost(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    var h = host;
    while (true) {
      if (_domains.contains(h)) return true;
      final idx = h.indexOf('.');
      if (idx < 0 || idx >= h.length - 1) return false;
      h = h.substring(idx + 1);
    }
  }

  /// 解析规则文本为域名集合（支持 hosts / AdGuard 风格）
  static Set<String> parseRules(String text) {
    final domains = <String>{};
    for (var line in text.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!') || line.startsWith('#')) continue;
      if (line.startsWith('[')) continue;
      // 例外规则不参与拦截
      if (line.startsWith('@@')) continue;
      final hostsMatch = _hostsLineRe.firstMatch(line);
      if (hostsMatch != null) {
        _addDomain(domains, hostsMatch.group(1)!);
        continue;
      }
      var token = line;
      if (token.startsWith('||')) {
        token = token.substring(2);
      } else if (token.startsWith('|')) {
        token = token.substring(1);
      }
      token = token.split(RegExp(r'[|^/$]')).first;
      _addDomain(domains, token);
    }
    return domains;
  }

  static void _addDomain(Set<String> domains, String raw) {
    var d = raw.trim().toLowerCase();
    if (d.isEmpty || d.contains('*')) return;
    if (d.startsWith('.')) d = d.substring(1);
    if (d.endsWith('.')) d = d.substring(0, d.length - 1);
    if (d.length > 253) return;
    if (!_domainRe.hasMatch(d)) return;
    domains.add(d);
  }
}
