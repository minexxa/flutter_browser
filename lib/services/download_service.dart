import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import 'settings_service.dart';

/// 内置下载器：http 流式下载，支持暂停 / 继续（Range 续传）/ 删除 / 重试
class DownloadService extends ChangeNotifier {
  DownloadService._();

  static final DownloadService instance = DownloadService._();

  static const String _prefsKey = 'download_tasks_v1';
  static int _idSeq = 0;

  final List<DownloadTask> _tasks = [];
  final Map<String, StreamSubscription<List<int>>> _subs = {};
  final Map<String, int> _progressStamp = {};
  final Map<String, DateTime> _lastStampTime = {};
  final http.Client _client = http.Client();

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();

  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.completed).toList();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isEmpty) return;
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final task = DownloadTask.fromJson(item as Map<String, dynamic>);
        // 上次退出时仍在下载的任务标记为已暂停（保留断点）
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued) {
          task.status = DownloadStatus.paused;
        }
        _tasks.add(task);
      }
    } catch (_) {
      // 任务列表损坏时从空开始
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_tasks.map((t) => t.toJson()).toList()),
    );
  }

  DownloadTask? taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 解析下载目录
  Future<Directory> _resolveDownloadDir() async {
    final configured = SettingsService.instance.downloadPath;
    if (configured != 'default' && configured.isNotEmpty) {
      final dir = Directory(configured);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    Directory base;
    try {
      base = (await getExternalStorageDirectory()) ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/Download');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 新增下载任务并开始下载
  Future<DownloadTask> startDownload(String url, {String? fileName}) async {
    final dir = await _resolveDownloadDir();
    final name = _resolveFileName(url, fileName);
    final savePath = _uniquePath(dir.path, name);

    final task = DownloadTask(
      id: 'dl_${++_idSeq}_${DateTime.now().millisecondsSinceEpoch}',
      url: url,
      fileName: savePath.split('/').last,
      savePath: savePath,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _tasks.insert(0, task);
    notifyListeners();
    await _persist();
    await _run(task);
    return task;
  }

  String _resolveFileName(String url, String? override) {
    if (override != null && override.trim().isNotEmpty) {
      return _sanitizeFileName(override.trim());
    }
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = Uri.decodeComponent(segments.last);
        if (last.contains('.')) return _sanitizeFileName(last);
      }
      if (uri.host.isNotEmpty) {
        return _sanitizeFileName('${uri.host}_${DateTime.now().millisecondsSinceEpoch}');
      }
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  String _uniquePath(String dir, String fileName) {
    var path = '$dir/$fileName';
    if (!File(path).existsSync()) return path;
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var i = 1;
    while (File(path).existsSync()) {
      path = '$dir/$base($i)$ext';
      i++;
    }
    return path;
  }

  /// 执行 / 继续下载
  Future<void> _run(DownloadTask task) async {
    if (task.status == DownloadStatus.completed) return;
    _subs[task.id]?.cancel();
    task.status = DownloadStatus.downloading;
    task.error = null;
    notifyListeners();

    final file = File(task.savePath);

    // 断点续传：以已接收字节数为准，文件被截断时按实际长度修正
    var existingBytes = task.receivedBytes;
    if (existingBytes > 0) {
      if (file.existsSync()) {
        final fileLength = await file.length();
        if (fileLength < existingBytes) {
          existingBytes = fileLength;
          task.receivedBytes = fileLength;
        }
      } else {
        existingBytes = 0;
        task.receivedBytes = 0;
      }
    }

    final request = http.Request('GET', Uri.parse(task.url));
    request.followRedirects = true;
    if (existingBytes > 0) {
      request.headers['Range'] = 'bytes=$existingBytes-';
    }

    try {
      final response = await _client.send(request).timeout(
            const Duration(seconds: 30),
          );
      if (task.status != DownloadStatus.downloading) return;

      if (response.statusCode == 206) {
        // 服务端支持 Range，追加写入
        task.totalBytes = existingBytes + (response.contentLength ?? 0);
        await _streamTo(task, response.stream, file, append: true);
      } else if (response.statusCode >= 200 && response.statusCode < 300) {
        // 服务端不支持 Range：从头下载
        task.receivedBytes = 0;
        task.totalBytes = response.contentLength ?? -1;
        await _streamTo(task, response.stream, file, append: false);
      } else {
        task.status = DownloadStatus.failed;
        task.error = 'HTTP ${response.statusCode}';
        notifyListeners();
        await _persist();
      }
    } catch (e) {
      if (task.status == DownloadStatus.paused) return;
      task.status = DownloadStatus.failed;
      task.error = _friendlyError(e);
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _streamTo(
    DownloadTask task,
    Stream<List<int>> stream,
    File file, {
    required bool append,
  }) async {
    final sink = file.openWrite(
      mode: append ? FileMode.writeOnlyAppend : FileMode.writeOnly,
    );
    var received = task.receivedBytes;
    _progressStamp[task.id] = received;
    _lastStampTime[task.id] = DateTime.now();

    final sub = stream.listen(
      (chunk) async {
        received += chunk.length;
        task.receivedBytes = received;
        sink.add(chunk);

        // 计算瞬时速度
        final now = DateTime.now();
        final lastTime = _lastStampTime[task.id]!;
        final elapsed = now.difference(lastTime).inMilliseconds;
        if (elapsed >= 500) {
          final lastBytes = _progressStamp[task.id] ?? 0;
          task.speed = ((received - lastBytes) * 1000 / elapsed).round();
          _progressStamp[task.id] = received;
          _lastStampTime[task.id] = now;
        }
        _notifyThrottled();
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        if (task.status != DownloadStatus.downloading) return;
        task.speed = 0;
        if (task.totalBytes > 0 && task.receivedBytes < task.totalBytes) {
          // 连接被提前关闭，视为失败以便重试
          task.status = DownloadStatus.failed;
          task.error = '连接中断';
        } else {
          task.status = DownloadStatus.completed;
        }
        _subs.remove(task.id);
        notifyListeners();
        await _persist();
      },
      onError: (Object error) async {
        await sink.flush();
        await sink.close();
        if (task.status == DownloadStatus.paused) return;
        task.status = DownloadStatus.failed;
        task.error = _friendlyError(error);
        _subs.remove(task.id);
        notifyListeners();
        await _persist();
      },
      cancelOnError: true,
    );
    _subs[task.id] = sub;
  }

  DateTime? _lastNotify;

  void _notifyThrottled() {
    final now = DateTime.now();
    if (_lastNotify == null || now.difference(_lastNotify!).inMilliseconds >= 250) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('SocketException') || text.contains('Failed host lookup')) {
      return '网络错误';
    }
    if (text.contains('TimeoutException') || text.contains('timeout')) {
      return '连接超时';
    }
    return '下载失败';
  }

  /// 暂停
  Future<void> pause(DownloadTask task) async {
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued) {
      return;
    }
    task.status = DownloadStatus.paused;
    task.speed = 0;
    final sub = _subs.remove(task.id);
    await sub?.cancel();
    notifyListeners();
    await _persist();
  }

  /// 继续 / 重试
  Future<void> resume(DownloadTask task) async {
    if (task.status == DownloadStatus.downloading) return;
    await _run(task);
  }

  /// 删除任务（同时删除文件）
  Future<void> deleteTask(DownloadTask task,
      {bool deleteFile = true}) async {
    final sub = _subs.remove(task.id);
    await sub?.cancel();
    if (deleteFile) {
      final file = File(task.savePath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
    await _persist();
  }

  /// 清除已完成记录（保留文件）
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    notifyListeners();
    await _persist();
  }

  /// 退出时清除数据
  Future<void> clearAll() async {
    for (final sub in _subs.values) {
      await sub.cancel();
    }
    _subs.clear();
    for (final task in _tasks) {
      final file = File(task.savePath);
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    _tasks.clear();
    notifyListeners();
    await _persist();
  }
}

/// 根据扩展名返回图标字符（下载列表用）
String fileIconChar(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  const map = {
    'apk': 'A',
    'zip': 'Z',
    'rar': 'R',
    '7z': '7',
    'pdf': 'P',
    'doc': 'W',
    'docx': 'W',
    'xls': 'X',
    'xlsx': 'X',
    'ppt': 'T',
    'pptx': 'T',
    'mp3': 'M',
    'flac': 'M',
    'wav': 'M',
    'mp4': 'V',
    'mkv': 'V',
    'avi': 'V',
    'mov': 'V',
    'jpg': 'I',
    'jpeg': 'I',
    'png': 'I',
    'gif': 'I',
    'webp': 'I',
  };
  return map[ext] ?? 'F';
}
