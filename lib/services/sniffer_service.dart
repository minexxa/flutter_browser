import 'package:flutter/foundation.dart';

/// 网页资源嗅探结果类型
enum SnifferKind {
  video,
  audio,
  other;

  static SnifferKind fromUrl(String url) {
    final lower = url.toLowerCase().split('?').first.split('#').first;
    if (lower.endsWith('.m3u8') ||
        lower.endsWith('.mpd') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.m4s') ||
        lower.endsWith('.webm')) {
      return SnifferKind.video;
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg')) {
      return SnifferKind.audio;
    }
    return SnifferKind.other;
  }
}

/// 网页资源嗅探服务：按标签页聚合嗅探到的媒体资源 URL
class SnifferService extends ChangeNotifier {
  SnifferService._();

  static final SnifferService instance = SnifferService._();

  /// tabId -> 保持插入顺序的资源列表
  final Map<String, List<String>> _byTab = {};

  List<String> forTab(String tabId) => List.unmodifiable(_byTab[tabId] ?? const []);

  bool hasForTab(String tabId) => (_byTab[tabId]?.isNotEmpty ?? false);

  int countForTab(String tabId) => _byTab[tabId]?.length ?? 0;

  /// 合并一批新嗅探到的 URL（自动去重，忽略空串与非 http 链接）
  void addAll(String tabId, List<String> urls) {
    if (urls.isEmpty) return;
    final list = _byTab.putIfAbsent(tabId, () => <String>[]);
    var changed = false;
    for (final url in urls) {
      if (url.isEmpty) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      if (list.contains(url)) continue;
      list.add(url);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void clearTab(String tabId) {
    if (_byTab.remove(tabId) != null) notifyListeners();
  }

  void clearAll() {
    if (_byTab.isEmpty) return;
    _byTab.clear();
    notifyListeners();
  }
}
