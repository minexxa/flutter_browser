/// 下载任务状态
enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed;

  static DownloadStatus fromString(String? value) => switch (value) {
        'queued' => DownloadStatus.queued,
        'downloading' => DownloadStatus.downloading,
        'paused' => DownloadStatus.paused,
        'completed' => DownloadStatus.completed,
        'failed' => DownloadStatus.failed,
        _ => DownloadStatus.queued,
      };
}

/// 下载任务
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalBytes = -1,
    this.receivedBytes = 0,
    this.status = DownloadStatus.queued,
    this.speed = 0,
    this.error,
    required this.createdAt,
  });

  final String id;
  final String url;
  final String fileName;
  final String savePath;
  int totalBytes; // -1 表示未知
  int receivedBytes;
  DownloadStatus status;
  int speed; // 字节/秒
  String? error;
  final int createdAt;

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.paused ||
      status == DownloadStatus.failed;

  double get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'savePath': savePath,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'status': status.name,
        'error': error,
        'createdAt': createdAt,
      };

  static DownloadTask fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        savePath: json['savePath'] as String,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? -1,
        receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
        status: DownloadStatus.fromString(json['status'] as String?),
        error: json['error'] as String?,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}
