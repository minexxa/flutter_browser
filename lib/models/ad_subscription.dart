/// 广告拦截规则订阅
class AdSubscription {
  AdSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.lastUpdated = 0,
    this.ruleCount = 0,
  });

  final String id;
  String name;
  String url;
  bool enabled;
  int lastUpdated; // millisecondsSinceEpoch
  int ruleCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'lastUpdated': lastUpdated,
        'ruleCount': ruleCount,
      };

  static AdSubscription fromJson(Map<String, dynamic> json) => AdSubscription(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        lastUpdated: (json['lastUpdated'] as num?)?.toInt() ?? 0,
        ruleCount: (json['ruleCount'] as num?)?.toInt() ?? 0,
      );
}
