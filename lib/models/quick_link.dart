/// 快捷网址（主页收藏）
class QuickLink {
  QuickLink({
    required this.id,
    required this.name,
    required this.url,
    this.colorValue = 0xFF1A73E8,
    this.iconChar,
  });

  final String id;
  String name;
  String url;
  int colorValue;
  String? iconChar;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'colorValue': colorValue,
        'iconChar': iconChar,
      };

  static QuickLink fromJson(Map<String, dynamic> json) => QuickLink(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF1A73E8,
        iconChar: json['iconChar'] as String?,
      );
}

/// 默认快捷网址，参考 Via 浏览器主页收藏常用站点
List<QuickLink> defaultQuickLinks() => [
      QuickLink(
        id: 'ql_baidu',
        name: '百度',
        url: 'https://m.baidu.com',
        colorValue: 0xFF2932E1,
        iconChar: '百',
      ),
      QuickLink(
        id: 'ql_bilibili',
        name: '哔哩哔哩',
        url: 'https://m.bilibili.com',
        colorValue: 0xFFFB7299,
        iconChar: 'B',
      ),
      QuickLink(
        id: 'ql_zhihu',
        name: '知乎',
        url: 'https://www.zhihu.com',
        colorValue: 0xFF0084FF,
        iconChar: '知',
      ),
      QuickLink(
        id: 'ql_weibo',
        name: '微博',
        url: 'https://m.weibo.cn',
        colorValue: 0xFFE6162D,
        iconChar: '微',
      ),
      QuickLink(
        id: 'ql_taobao',
        name: '淘宝',
        url: 'https://m.taobao.com',
        colorValue: 0xFFFF5000,
        iconChar: '淘',
      ),
      QuickLink(
        id: 'ql_jd',
        name: '京东',
        url: 'https://m.jd.com',
        colorValue: 0xFFE1251B,
        iconChar: '京',
      ),
      QuickLink(
        id: 'ql_vqq',
        name: '腾讯视频',
        url: 'https://m.v.qq.com',
        colorValue: 0xFF006EFF,
        iconChar: '腾',
      ),
      QuickLink(
        id: 'ql_163',
        name: '网易新闻',
        url: 'https://3g.163.com',
        colorValue: 0xFFE60012,
        iconChar: '网',
      ),
    ];
