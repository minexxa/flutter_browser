import 'package:flutter/material.dart';

import '../models/download_task.dart';
import '../services/download_service.dart';
import '../utils/url_utils.dart';

/// 下载管理页（内置下载器）
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DownloadService.instance;
    return DefaultTabController(
      length: 2,
      child: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('下载管理'),
              bottom: TabBar(
                tabs: [
                  Tab(text: '正在下载 (${service.activeTasks.length})'),
                  Tab(text: '已下载 (${service.completedTasks.length})'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildTaskList(context, service.activeTasks),
                _buildCompletedList(context, service.completedTasks),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => _showNewDownloadDialog(context),
              tooltip: '新建下载',
              child: const Icon(Icons.add),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompletedList(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return _buildTaskList(context, tasks);
    }
    return Column(
      children: [
        Expanded(
          child: _buildTaskList(context, tasks),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: OutlinedButton.icon(
              onPressed: () async {
                await DownloadService.instance.clearCompleted();
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('清除已完成记录'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(BuildContext context, List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无下载任务',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildTaskTile(context, tasks[index]),
    );
  }

  Widget _buildTaskTile(BuildContext context, DownloadTask task) {
    final theme = Theme.of(context);
    final statusText = _statusText(task);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              fileIconChar(task.fileName),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (task.status == DownloadStatus.downloading) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 5,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
                if (task.status == DownloadStatus.paused &&
                    task.totalBytes > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 5,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          _buildActions(context, task),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, DownloadTask task) {
    final service = DownloadService.instance;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued)
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: '暂停',
            onPressed: () => service.pause(task),
          ),
        if (task.status == DownloadStatus.paused ||
            task.status == DownloadStatus.failed)
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: task.status == DownloadStatus.failed ? '重试' : '继续',
            onPressed: () => service.resume(task),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '删除',
          onPressed: () => _confirmDelete(context, task),
        ),
      ],
    );
  }

  String _statusText(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.queued:
        return '等待中 · ${formatBytes(task.receivedBytes)}';
      case DownloadStatus.downloading:
        if (task.totalBytes > 0) {
          return '${formatBytes(task.receivedBytes)}/${formatBytes(task.totalBytes)}'
              ' · ${formatSpeed(task.speed)}';
        }
        return '${formatBytes(task.receivedBytes)} · ${formatSpeed(task.speed)}';
      case DownloadStatus.paused:
        if (task.totalBytes > 0) {
          return '已暂停 · ${formatBytes(task.receivedBytes)}/${formatBytes(task.totalBytes)}';
        }
        return '已暂停 · ${formatBytes(task.receivedBytes)}';
      case DownloadStatus.completed:
        return formatBytes(task.totalBytes > 0 ? task.totalBytes : task.receivedBytes);
      case DownloadStatus.failed:
        return task.error ?? '下载失败';
    }
  }

  void _confirmDelete(BuildContext context, DownloadTask task) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除这个下载任务吗？'),
          content: Text(task.fileName),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await DownloadService.instance.deleteTask(task);
              },
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }

  void _showNewDownloadDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('新建下载'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '下载链接',
              hintText: 'https://',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isEmpty) return;
                Navigator.pop(dialogContext);
                await DownloadService.instance.startDownload(url);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已开始下载')),
                );
              },
              child: const Text('下载'),
            ),
          ],
        );
      },
    );
  }
}
