import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';
import '../models/quick_link.dart';

/// 本地数据服务：快捷网址、浏览历史、标签页恢复
class BrowserDataService {
  BrowserDataService._();

  static final BrowserDataService instance = BrowserDataService._();

  static const String _quickLinksKey = 'quick_links_v1';
  static const String _historyKey = 'history_v1';
  static const String _tabsKey = 'open_tabs_v1';
  static const String _passwordsKey = 'saved_passwords_v1';
  static const int _historyLimit = 200;

  List<QuickLink>? _quickLinks;
  List<HistoryEntry>? _history;

  // ---- 快捷网址 ----

  Future<List<QuickLink>> quickLinks() async {
    if (_quickLinks != null) return _quickLinks!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_quickLinksKey);
    if (raw == null || raw.isEmpty) {
      _quickLinks = defaultQuickLinks();
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _quickLinks = list
            .map((e) => QuickLink.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _quickLinks = defaultQuickLinks();
      }
    }
    return _quickLinks!;
  }

  Future<void> saveQuickLinks(List<QuickLink> links) async {
    _quickLinks = List.of(links);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _quickLinksKey,
      jsonEncode(links.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addQuickLink(QuickLink link) async {
    final links = await quickLinks();
    links.add(link);
    await saveQuickLinks(links);
  }

  Future<void> updateQuickLink(QuickLink link) async {
    final links = await quickLinks();
    final index = links.indexWhere((e) => e.id == link.id);
    if (index >= 0) {
      links[index] = link;
      await saveQuickLinks(links);
    }
  }

  Future<void> removeQuickLink(String id) async {
    final links = await quickLinks();
    links.removeWhere((e) => e.id == id);
    await saveQuickLinks(links);
  }

  // ---- 浏览历史 ----

  Future<List<HistoryEntry>> history() async {
    if (_history != null) return _history!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      _history = [];
    } else {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _history = list
            .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _history = [];
      }
    }
    return _history!;
  }

  Future<void> addHistory(String url, String title) async {
    if (url.isEmpty || url.startsWith('about:')) return;
    final entries = await history();
    entries.removeWhere((e) => e.url == url);
    entries.insert(
      0,
      HistoryEntry(
        url: url,
        title: title.isEmpty ? url : title,
        visitedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (entries.length > _historyLimit) {
      entries.removeRange(_historyLimit, entries.length);
    }
    await _persistHistory(entries);
  }

  Future<void> removeHistory(String url) async {
    final entries = await history();
    entries.removeWhere((e) => e.url == url);
    await _persistHistory(entries);
  }

  Future<void> clearHistory() async {
    await _persistHistory([]);
  }

  Future<void> _persistHistory(List<HistoryEntry> entries) async {
    _history = entries;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  // ---- 标签页恢复 ----

  Future<void> saveOpenTabs(List<Map<String, String>> tabs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tabsKey, jsonEncode(tabs));
  }

  Future<List<Map<String, String>>> loadOpenTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tabsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Map<String, String>.from(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearOpenTabs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tabsKey);
  }

  // ---- 保存的密码 ----

  /// host -> {username, password}
  Future<Map<String, Map<String, String>>> savedPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_passwordsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(
            key,
            Map<String, String>.from(value as Map<String, dynamic>),
          ));
    } catch (_) {
      return {};
    }
  }

  Future<void> savePassword(
      String host, String username, String password) async {
    final passwords = await savedPasswords();
    passwords[host] = {'username': username, 'password': password};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordsKey, jsonEncode(passwords));
  }

  Future<void> clearPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordsKey);
  }
}
