import 'package:flutter/material.dart';

import '../models/browser_tab.dart';

/// 多窗口管理页（参考 Via 多标签视图）
class TabsPage extends StatelessWidget {
  const TabsPage({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onSelect,
    required this.onClose,
    required this.onNewTab,
    required this.onCloseAll,
  });

  final List<BrowserTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onNewTab;
  final VoidCallback onCloseAll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('标签页 (${tabs.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建标签页',
            onPressed: onNewTab,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '关闭所有标签',
            onPressed: onCloseAll,
          ),
        ],
      ),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: tabs.length,
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final selected = index == currentIndex;
            return _TabCard(
              tab: tab,
              selected: selected,
              onTap: () => onSelect(index),
              onClose: () => onClose(index),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: onCloseAll,
                icon: const Icon(Icons.delete_outline),
                label: const Text('关闭所有标签'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onNewTab,
                icon: const Icon(Icons.add),
                label: const Text('新建标签页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final BrowserTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = tab.title.characters.first.toUpperCase();
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.isHome ? '首页' : tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onClose,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: tab.isHome
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.home_outlined,
                              size: 36,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '首页',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          tab.url,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              if (tab.isLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    value: tab.progress / 100,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
