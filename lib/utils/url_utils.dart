// URL / 搜索引擎工具

/// 搜索引擎配置
class SearchEngine {
  const SearchEngine(this.key, this.label, this.searchUrl);

  final String key;
  final String label;
  final String searchUrl; // {query} 为占位符

  static const baidu = SearchEngine('baidu', '百度', 'https://www.baidu.com/s?wd={query}');
  static const bing = SearchEngine('bing', '必应', 'https://cn.bing.com/search?q={query}');
  static const google = SearchEngine('google', '谷歌', 'https://www.google.com/search?q={query}');
  static const sogou = SearchEngine('sogou', '搜狗', 'https://www.sogou.com/web?query={query}');
  static const so360 = SearchEngine('so360', '360搜索', 'https://www.so.com/s?q={query}');
  static const toutiao = SearchEngine('toutiao', '头条', 'https://so.toutiao.com/search?keyword={query}');

  static const List<SearchEngine> builtin = [baidu, bing, google, sogou, so360, toutiao];

  static SearchEngine byKey(String key) =>
      builtin.firstWhere((e) => e.key == key, orElse: () => baidu);

  String buildUrl(String query) =>
      searchUrl.replaceAll('{query}', Uri.encodeComponent(query));
}

/// 浏览器标识（User-Agent）
class BrowserIdentity {
  const BrowserIdentity(this.key, this.label, this.userAgent);

  final String key;
  final String label;
  /// null 表示使用系统默认（Android 移动版）
  final String? userAgent;

  static const android = BrowserIdentity('android', 'Android', null);
  static const iphone = BrowserIdentity(
    'iphone',
    'iPhone',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );
  static const ipad = BrowserIdentity(
    'ipad',
    'iPad',
    'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  );
  static const pc = BrowserIdentity(
    'pc',
    '电脑',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  );

  static const List<BrowserIdentity> builtin = [android, iphone, ipad, pc];

  static BrowserIdentity byKey(String key) =>
      builtin.firstWhere((e) => e.key == key, orElse: () => android);
}

/// 将用户输入规范化为可加载的 URL；无法识别为网址时按搜索引擎处理
String normalizeInput(String input, {required SearchEngine engine}) {
  final text = input.trim();
  if (text.isEmpty) return '';

  // 已是完整 URL
  final lower = text.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://') ||
      lower.startsWith('file://')) {
    return text;
  }

  // about:blank 等特殊页面
  if (lower.startsWith('about:') || lower.startsWith('javascript:')) {
    return text;
  }

  // 形似域名（含点且无空格）→ 补 https://
  final looksLikeHost = RegExp(r'^[^\s/]+\.[^\s/]{2,}(/.*)?$').hasMatch(text) &&
      !text.contains(' ');
  if (looksLikeHost) {
    return 'https://$text';
  }

  // 其余按搜索处理
  return engine.buildUrl(text);
}

/// 从 URL 提取用于显示的主机名
String hostOf(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.host.isNotEmpty) return uri.host;
  } catch (_) {}
  return url;
}

/// 文件名是否看起来是可下载资源
bool looksDownloadable(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  const exts = [
    'apk', 'zip', 'rar', '7z', 'gz', 'tar', 'bz2', 'xz',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md',
    'mp3', 'wav', 'flac', 'aac', 'm4a',
    'mp4', 'avi', 'mkv', 'flv', 'mov', 'wmv', 'ts',
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
    'exe', 'dmg', 'iso', 'img', 'torrent',
  ];
  for (final ext in exts) {
    if (path.endsWith('.$ext')) return true;
  }
  return false;
}

/// 格式化文件大小
String formatBytes(int bytes) {
  if (bytes < 0) return '未知大小';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 格式化速度
String formatSpeed(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';
