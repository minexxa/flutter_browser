import 'package:flutter/material.dart';

import '../models/history_entry.dart';
import '../models/quick_link.dart';
import '../services/browser_data_service.dart';
import 'bookmarks_page.dart';
import 'history_page.dart';

/// Via 风格首页：logo + 搜索框 + 快捷网址 + 最近浏览
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.onSearch,
    required this.onOpenUrl,
    required this.onOpenSettings,
    required this.onOpenDownloads,
    required this.onClearHistory,
  });

  final ValueChanged<String> onSearch;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDownloads;
  final VoidCallback onClearHistory;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<QuickLink> _links = [];
  List<HistoryEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final links = List.of(await BrowserDataService.instance.quickLinks());
    final history = List.of(await BrowserDataService.instance.history());
    if (!mounted) return;
    setState(() {
      _links = links;
      _history = history;
    });
  }

  /// 供外部调用：刷新快捷网址与历史数据
  Future<void> reload() => _reload();

  void _submitSearch() {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    _searchFocus.unfocus();
    widget.onSearch(text);
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildHeader(theme),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _buildQuickLinksSection(theme),
              const SizedBox(height: 8),
              _buildHistorySection(theme),
            ],
          ),
        ),
      ],
    );
  }

  // ---- 顶部：logo + 搜索框 + 菜单 ----

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const BrowserLogo(size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(),
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: '搜索或输入网址',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '菜单',
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  widget.onOpenSettings();
                  break;
                case 'downloads':
                  widget.onOpenDownloads();
                  break;
                case 'bookmarks':
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const BookmarksPage(),
                    ),
                  );
                  break;
                case 'history':
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const HistoryPage(),
                    ),
                  );
                  break;
                case 'clear_history':
                  _confirmClearHistory();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'downloads',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('下载管理'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'bookmarks',
                child: ListTile(
                  leading: Icon(Icons.star_outline),
                  title: Text('书签'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('历史记录'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear_history',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('清除浏览历史'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('设置'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 快捷访问 ----

  Widget _buildQuickLinksSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Text(
                '快捷访问',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_links.isNotEmpty)
                TextButton(
                  onPressed: _editLinks,
                  child: const Text('管理'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            mainAxisSpacing: 4,
            crossAxisSpacing: 0,
            childAspectRatio: 0.78,
            children: [
              ..._links.map(_buildQuickLinkTile),
              _buildAddLinkTile(theme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickLinkTile(QuickLink link) {
    final theme = Theme.of(context);
    final initial = link.iconChar?.isNotEmpty == true
        ? link.iconChar!
        : link.name.characters.first;
    return InkWell(
      onTap: () => widget.onOpenUrl(link.url),
      onLongPress: () => _showLinkMenu(link),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(link.colorValue),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              link.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddLinkTile(ThemeData theme) {
    return InkWell(
      onTap: () => _showLinkDialog(null),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.colorScheme.outlineVariant,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '添加',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 最近浏览 ----

  Widget _buildHistorySection(ThemeData theme) {
    final recent = _history.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Text(
                '最近浏览',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (recent.isNotEmpty)
                TextButton(
                  onPressed: _confirmClearHistory,
                  child: const Text('清除'),
                ),
            ],
          ),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Text(
              '暂无浏览记录',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...recent.map((entry) => _buildHistoryTile(theme, entry)),
      ],
    );
  }

  Widget _buildHistoryTile(ThemeData theme, HistoryEntry entry) {
    return ListTile(
      dense: true,
      onTap: () => widget.onOpenUrl(entry.url),
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
        style: theme.textTheme.bodyMedium,
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
    );
  }

  // ---- 交互 ----

  void _showLinkMenu(QuickLink link) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                _showLinkDialog(link);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () async {
                Navigator.pop(context);
                await BrowserDataService.instance.removeQuickLink(link.id);
                await _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  static const List<int> _presetColors = [
    0xFF1A73E8,
    0xFFE6162D,
    0xFFFF5000,
    0xFFFB7299,
    0xFF00A578,
    0xFF7B1FA2,
    0xFF0084FF,
    0xFF00695C,
  ];

  void _showLinkDialog(QuickLink? link) {
    final isEdit = link != null;
    final nameController = TextEditingController(text: link?.name ?? '');
    final urlController = TextEditingController(text: link?.url ?? '');
    int colorValue = link?.colorValue ?? _presetColors[0];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? '编辑快捷网址' : '添加快捷网址'),
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presetColors.map((color) {
                        final selected = color == colorValue;
                        return GestureDetector(
                          onTap: () =>
                              setDialogState(() => colorValue = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: selected
                                  ? Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: selected
                                ? const Icon(Icons.check,
                                    size: 18, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
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
                    final name = nameController.text.trim();
                    var url = urlController.text.trim();
                    if (name.isEmpty || url.isEmpty) return;
                    if (!url.startsWith('http://') &&
                        !url.startsWith('https://')) {
                      url = 'https://$url';
                    }
                    final service = BrowserDataService.instance;
                    if (isEdit) {
                      await service.updateQuickLink(QuickLink(
                        id: link.id,
                        name: name,
                        url: url,
                        colorValue: colorValue,
                        iconChar: link.iconChar,
                      ));
                    } else {
                      await service.addQuickLink(QuickLink(
                        id: 'ql_${DateTime.now().millisecondsSinceEpoch}',
                        name: name,
                        url: url,
                        colorValue: colorValue,
                      ));
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
      },
    );
  }

  void _editLinks() {
    // 长按提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('长按图标可编辑或删除'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除浏览历史'),
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
              widget.onClearHistory();
              await _reload();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 浏览器 Logo（纸飞机造型）
class BrowserLogo extends StatelessWidget {
  const BrowserLogo({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 外层蓝色折纸
    final outer = Path()
      ..moveTo(w * 0.06, h * 0.60)
      ..lineTo(w * 0.94, h * 0.06)
      ..lineTo(w * 0.44, h * 0.94)
      ..lineTo(w * 0.36, h * 0.62)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFF00A5F6));

    // 内层橙色折面
    final inner = Path()
      ..moveTo(w * 0.42, h * 0.90)
      ..lineTo(w * 0.92, h * 0.12)
      ..lineTo(w * 0.52, h * 0.64)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFF3E00));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
