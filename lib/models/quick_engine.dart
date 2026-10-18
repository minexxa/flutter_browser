/// 快捷搜索引擎（参考"移动端搜索引擎快捷切换"脚本）
class QuickEngine {
  const QuickEngine({
    required this.name,
    required this.host,
    required this.url,
  });

  final String name;

  /// 用于判断当前所在引擎的域名片段（可含路径，如 yandex.com/images）
  final String host;

  /// 搜索地址模板，{q} 为关键字占位符
  final String url;

  /// 用关键字构建跳转地址；模板无 {q} 时按 q= 参数拼接
  String buildUrl(String query) {
    final encoded = Uri.encodeComponent(query);
    if (url.contains('{q}')) {
      return url.replaceAll('{q}', encoded);
    }
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}q=$encoded';
  }

  QuickEngine copyWith({String? name, String? host, String? url}) =>
      QuickEngine(
        name: name ?? this.name,
        host: host ?? this.host,
        url: url ?? this.url,
      );

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'url': url};

  static QuickEngine fromJson(Map<String, dynamic> json) => QuickEngine(
        name: json['name'] as String? ?? '',
        host: json['host'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  /// 默认引擎列表（与脚本 DEFAULT_ENGINES 一致）
  static const List<QuickEngine> defaults = [
    QuickEngine(
      name: '必应',
      host: 'bing.com',
      url: 'https://cn.bing.com/search?q={q}',
    ),
    QuickEngine(
      name: '谷歌',
      host: 'google.com',
      url: 'https://www.google.com/search?q={q}',
    ),
    QuickEngine(
      name: '百度',
      host: 'baidu.com',
      url: 'https://www.baidu.com/s?wd={q}',
    ),
    QuickEngine(
      name: 'Yandex',
      host: 'yandex.com',
      url: 'https://yandex.com/search/?text={q}',
    ),
    QuickEngine(
      name: '夸克',
      host: 'quark.sm.cn',
      url: 'https://quark.sm.cn/s?q={q}',
    ),
    QuickEngine(
      name: '搜狗',
      host: 'sogou.com',
      url: 'https://www.sogou.com/web?query={q}',
    ),
    QuickEngine(
      name: 'Brave',
      host: 'brave.com',
      url: 'https://search.brave.com/search?q={q}',
    ),
  ];
}
