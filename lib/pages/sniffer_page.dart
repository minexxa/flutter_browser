import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';
import '../services/sniffer_service.dart';

/// 资源嗅探页：展示当前标签页嗅探到的媒体资源
class SnifferPage extends StatefulWidget {
  const SnifferPage({
    super.key,
    required this.tabId,
    required this.onOpenInNewTab,
  });

  final String tabId;
  final void Function(String url) onOpenInNewTab;

  @override
  State<SnifferPage> createState() => _SnifferPageState();
}

class _SnifferPageState extends State<SnifferPage> {
  @override
  void initState() {
    super.initState();
    SnifferService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    SnifferService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  IconData _iconFor(SnifferKind kind) {
    switch (kind) {
      case SnifferKind.video:
        return Icons.movie_outlined;
      case SnifferKind.audio:
        return Icons.music_note_outlined;
      case SnifferKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _kindLabel(SnifferKind kind) {
    switch (kind) {
      case SnifferKind.video:
        return '视频';
      case SnifferKind.audio:
        return '音频';
      case SnifferKind.other:
        return '资源';
    }
  }

  String _fileNameFromUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const [];
    final last = segments.isNotEmpty ? segments.last : '';
    if (last.contains('.')) return last;
    return 'media_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _download(String url) async {
    await DownloadService.instance.startDownload(
      url,
      fileName: _fileNameFromUrl(url),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入下载列表')),
    );
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resources = SnifferService.instance.forTab(widget.tabId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('资源嗅探'),
        actions: [
          if (resources.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  SnifferService.instance.clearTab(widget.tabId),
            ),
        ],
      ),
      body: resources.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.travel_explore, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      '尚未嗅探到媒体资源\n播放页面中的音视频后再试，或刷新页面重新嗅探',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: resources.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final url = resources[index];
                final kind = SnifferKind.fromUrl(url);
                return ListTile(
                  leading: Icon(_iconFor(kind), color: theme.colorScheme.primary),
                  title: Text(
                    _fileNameFromUrl(url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_kindLabel(kind)} · $url',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  isThreeLine: false,
                  trailing: PopupMenuButton<String>(
                    tooltip: '更多',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      switch (value) {
                        case 'download':
                          _download(url);
                        case 'copy':
                          _copy(url);
                        case 'open':
                          Navigator.of(context).pop();
                          widget.onOpenInNewTab(url);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'download', child: Text('下载')),
                      PopupMenuItem(value: 'copy', child: Text('复制链接')),
                      PopupMenuItem(value: 'open', child: Text('新标签页打开')),
                    ],
                  ),
                  onTap: () => _download(url),
                );
              },
            ),
    );
  }
}
