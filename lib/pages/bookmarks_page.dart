import 'package:flutter/material.dart';

import '../models/bookmark.dart';
import '../models/quick_link.dart';
import '../services/browser_data_service.dart';
import 'shell_page.dart';

/// 书签管理页（参考 Via 书签）
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<Bookmark> _bookmarks = [];
  String _keyword = '';
  bool _searching = false;
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
    final list = List.of(await BrowserDataService.instance.bookmarks());
    if (!mounted) return;
    setState(() => _bookmarks = list);
  }

  List<Bookmark> get _filtered {
    if (_keyword.isEmpty) return _bookmarks;
    final kw = _keyword.toLowerCase();
    return _bookmarks
        .where((e) =>
            e.name.toLowerCase().contains(kw) || e.url.toLowerCase().contains(kw))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: _searching ? _buildSearchField(theme) : const Text('书签'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? '关闭搜索' : '搜索书签',
            onPressed: () {
              setState(() {
                _searching = !_searching;
                _keyword = '';
                _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加书签',
            onPressed: () => _showEditDialog(null),
          ),
        ],
      ),
      body: list.isEmpty
          ? _buildEmpty(theme)
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) => _buildTile(theme, list[index]),
            ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '搜索书签',
        border: InputBorder.none,
        suffixIcon: _keyword.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _keyword = '');
                },
              )
            : null,
      ),
      onChanged: (value) => setState(() => _keyword = value.trim()),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_outline,
              size: 48, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            _keyword.isEmpty ? '暂无书签' : '没有匹配的书签',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(ThemeData theme, Bookmark bookmark) {
    return ListTile(
      leading: const Icon(Icons.star_outline),
      title: Text(
        bookmark.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        bookmark.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '更多',
        onSelected: (value) => _onMenu(value, bookmark),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'home', child: Text('添加到主页')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: () =>
          shellPageKey.currentState?.openUrlFromAnywhere(bookmark.url),
    );
  }

  void _onMenu(String value, Bookmark bookmark) {
    switch (value) {
      case 'edit':
        _showEditDialog(bookmark);
        break;
      case 'home':
        _addToHome(bookmark);
        break;
      case 'delete':
        _confirmDelete(bookmark);
        break;
    }
  }

  Future<void> _addToHome(Bookmark bookmark) async {
    await BrowserDataService.instance.addQuickLink(
      QuickLink(
        id: 'ql_${DateTime.now().millisecondsSinceEpoch}',
        name: bookmark.name,
        url: bookmark.url,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加到主页快捷访问')),
    );
  }

  void _confirmDelete(Bookmark bookmark) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除书签'),
        content: Text('确定要删除“${bookmark.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await BrowserDataService.instance.removeBookmark(bookmark.id);
              await _reload();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Bookmark? bookmark) {
    final isEdit = bookmark != null;
    final nameController = TextEditingController(text: bookmark?.name ?? '');
    final urlController = TextEditingController(text: bookmark?.url ?? '');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? '编辑书签' : '添加书签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：百度',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '网址',
                  hintText: '例如：m.baidu.com',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                var name = nameController.text.trim();
                var url = urlController.text.trim();
                if (url.isEmpty) return;
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                if (name.isEmpty) name = url;
                final service = BrowserDataService.instance;
                if (isEdit) {
                  await service.updateBookmark(Bookmark(
                    id: bookmark.id,
                    name: name,
                    url: url,
                    createdAt: bookmark.createdAt,
                  ));
                } else {
                  await service.addBookmark(name, url);
                }
                if (context.mounted) Navigator.pop(context);
                await _reload();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}
