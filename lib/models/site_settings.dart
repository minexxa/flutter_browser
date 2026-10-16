/// 网站设置（按站点覆盖全局设置，参考 Via 网站设置）
class SiteSettings {
  SiteSettings({
    required this.host,
    this.userAgent,
    this.javaScript,
    this.cookies,
    this.images,
    this.adBlock,
  });

  final String host;

  /// null=跟随全局；'desktop'=桌面版；'mobile'=移动版；其他字符串=自定义 UA
  String? userAgent;

  /// null=跟随全局(开)；true=启用；false=禁用
  bool? javaScript;

  /// null=跟随全局(允许)；true=允许；false=禁止
  bool? cookies;

  /// null=跟随全局(允许)；false=阻止图片
  bool? images;

  /// null=跟随全局；true=启用；false=禁用
  bool? adBlock;

  bool get isEmpty =>
      userAgent == null &&
      javaScript == null &&
      cookies == null &&
      images == null &&
      adBlock == null;

  static const Object _unset = Object();

  /// 复制并修改字段；显式传 null 表示恢复"跟随全局"
  SiteSettings copyWith({
    Object? userAgent = _unset,
    Object? javaScript = _unset,
    Object? cookies = _unset,
    Object? images = _unset,
    Object? adBlock = _unset,
  }) =>
      SiteSettings(
        host: host,
        userAgent:
            userAgent == _unset ? this.userAgent : userAgent as String?,
        javaScript:
            javaScript == _unset ? this.javaScript : javaScript as bool?,
        cookies: cookies == _unset ? this.cookies : cookies as bool?,
        images: images == _unset ? this.images : images as bool?,
        adBlock: adBlock == _unset ? this.adBlock : adBlock as bool?,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        if (userAgent != null) 'userAgent': userAgent,
        if (javaScript != null) 'javaScript': javaScript,
        if (cookies != null) 'cookies': cookies,
        if (images != null) 'images': images,
        if (adBlock != null) 'adBlock': adBlock,
      };

  static SiteSettings fromJson(Map<String, dynamic> json) => SiteSettings(
        host: json['host'] as String,
        userAgent: json['userAgent'] as String?,
        javaScript: json['javaScript'] as bool?,
        cookies: json['cookies'] as bool?,
        images: json['images'] as bool?,
        adBlock: json['adBlock'] as bool?,
      );
}
