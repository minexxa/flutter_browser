import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quick_engine.dart';

/// 快捷引擎服务：引擎列表的加载 / 持久化 / 变更通知
class QuickEngineService extends ChangeNotifier {
  QuickEngineService._();

  static final QuickEngineService instance = QuickEngineService._();

  static const String _prefsKey = 'quick_engines_v1';

  List<QuickEngine> _engines = List.of(QuickEngine.defaults);
  bool _loaded = false;

  List<QuickEngine> get engines => List.unmodifiable(_engines);

  bool get isDefault =>
      _engines.length == QuickEngine.defaults.length &&
      _engines.asMap().entries.every(
            (e) =>
                e.value.name == QuickEngine.defaults[e.key].name &&
                e.value.host == QuickEngine.defaults[e.key].host &&
                e.value.url == QuickEngine.defaults[e.key].url,
          );

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.isNotEmpty) {
          _engines = decoded
              .whereType<Map<String, dynamic>>()
              .map(QuickEngine.fromJson)
              .toList();
        }
      } catch (_) {
        // 配置损坏时保留默认列表
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_engines.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 添加自定义引擎；URL 无 {q} 时自动补 q= 参数
  Future<void> add(String name, String url) async {
    final trimmedName = name.trim();
    var trimmedUrl = url.trim();
    if (trimmedName.isEmpty || trimmedUrl.isEmpty) return;
    if (!trimmedUrl.contains('{q}')) {
      final separator = trimmedUrl.contains('?') ? '&' : '?';
      trimmedUrl = '$trimmedUrl${separator}q={q}';
    }
    var host = trimmedName;
    try {
      host = Uri.parse(trimmedUrl.replaceAll('{q}', '')).host;
    } catch (_) {
      // 提取失败时以名称兜底
    }
    _engines = List.of(_engines)
      ..add(QuickEngine(name: trimmedName, host: host, url: trimmedUrl));
    await _persist();
  }

  Future<void> update(int index, String name, String url) async {
    if (index < 0 || index >= _engines.length) return;
    final trimmedName = name.trim();
    var trimmedUrl = url.trim();
    if (trimmedName.isEmpty || trimmedUrl.isEmpty) return;
    if (!trimmedUrl.contains('{q}')) {
      final separator = trimmedUrl.contains('?') ? '&' : '?';
      trimmedUrl = '$trimmedUrl${separator}q={q}';
    }
    var host = trimmedName;
    try {
      host = Uri.parse(trimmedUrl.replaceAll('{q}', '')).host;
    } catch (_) {
      // 提取失败时以名称兜底
    }
    final list = List.of(_engines);
    list[index] = QuickEngine(name: trimmedName, host: host, url: trimmedUrl);
    _engines = list;
    await _persist();
  }

  /// 删除引擎；至少保留一个
  Future<bool> removeAt(int index) async {
    if (index < 0 || index >= _engines.length) return false;
    if (_engines.length <= 1) return false;
    _engines = List.of(_engines)..removeAt(index);
    await _persist();
    return true;
  }

  Future<void> move(int from, int to) async {
    if (from < 0 || from >= _engines.length) return;
    if (to < 0 || to >= _engines.length) return;
    final list = List.of(_engines);
    final item = list.removeAt(from);
    list.insert(to, item);
    _engines = list;
    await _persist();
  }

  Future<void> resetToDefault() async {
    _engines = List.of(QuickEngine.defaults);
    await _persist();
  }
}
