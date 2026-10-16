import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../services/browser_data_service.dart';
import 'shell_page.dart';

/// 历史记录页（参考 Via 历史记录：搜索 / 按日期分组 / 删除 / 清空）
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> _history = [];
  String _keyword = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = List.of(await BrowserDataService.instance.history());
    if (!mounted) return;
    setState(() => _history = list);
  }

  List<HistoryEntry> get _filtered {
    if (_keyword.isEmpty) return _history;
    final kw = _keyword.toLowerCase();
    return _history
        .where((e) =>
            e.title.toLowerCase().contains(kw) || e.url.toLowerCase().contains(kw))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除全部历史',
            onPressed: _history.isEmpty ? null : _confirmClearAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索历史记录',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _keyword.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              onChanged: (value) => setState(() => _keyword = value.trim()),
            ),
          ),
        ),
      ),
      body: list.isEmpty
          ? _buildEmpty(theme)
          : ListView.builder(
              itemCount: list.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return const SizedBox(height: 4);
                final entry = list[index - 1];
                return _buildTile(theme, entry, list, index - 1);
              },
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history,
              size: 48, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            _keyword.isEmpty ? '暂无浏览记录' : '没有匹配的记录',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
      ThemeData theme, HistoryEntry entry, List<HistoryEntry> list, int index) {
    final showHeader = index == 0 || !_sameDay(list[index - 1], entry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              _dateLabel(entry),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ListTile(
          dense: true,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.public,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            entry.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '删除记录',
            onPressed: () async {
              await BrowserDataService.instance.removeHistory(entry.url);
              await _reload();
            },
          ),
          onTap: () =>
              shellPageKey.currentState?.openUrlFromAnywhere(entry.url),
        ),
      ],
    );
  }

  bool _sameDay(HistoryEntry a, HistoryEntry b) {
    final da = DateTime.fromMillisecondsSinceEpoch(a.visitedAt);
    final db = DateTime.fromMillisecondsSinceEpoch(b.visitedAt);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  String _dateLabel(HistoryEntry entry) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(entry.visitedAt);
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff <= 0) return '今天';
    if (diff == 1) return '昨天';
    return '${date.month}月${date.day}日';
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除历史记录'),
        content: const Text('确定要清除全部浏览历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await BrowserDataService.instance.clearHistory();
              await _reload();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
