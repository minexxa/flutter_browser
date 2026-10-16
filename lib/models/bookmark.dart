/// 书签（收藏）
class Bookmark {
  Bookmark({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
  });

  final String id;
  String name;
  String url;
  int createdAt; // millisecondsSinceEpoch

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'createdAt': createdAt,
      };

  static Bookmark fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}
