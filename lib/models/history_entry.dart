/// 浏览历史记录
class HistoryEntry {
  HistoryEntry({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final String url;
  String title;
  int visitedAt; // millisecondsSinceEpoch

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'visitedAt': visitedAt,
      };

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
        url: json['url'] as String,
        title: json['title'] as String? ?? json['url'] as String,
        visitedAt: (json['visitedAt'] as num?)?.toInt() ?? 0,
      );
}
