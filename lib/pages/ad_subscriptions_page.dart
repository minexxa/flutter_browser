import 'package:flutter/material.dart';

import '../models/ad_subscription.dart';
import '../services/ad_rule_service.dart';

/// 广告拦截规则订阅管理页（参考 Via 广告拦截订阅）
class AdSubscriptionsPage extends StatelessWidget {
  const AdSubscriptionsPage({super.key});

  static String _formatTime(int millis) {
    if (millis <= 0) return '从未更新';
    final t = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = AdRuleService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('广告拦截规则订阅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '全部更新',
            onPressed: service.updating
                ? null
                : () async {
                    try {
                      await service.updateAll();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('规则已更新')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('更新失败：$e')),
                      );
                    }
                  },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final subs = service.subscriptions;
          return Column(
            children: [
              if (subs.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '已启用规则 ${service.ruleCount} 条（含内建规则）',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (service.updating)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: subs.isEmpty
                    ? _buildEmpty(theme)
                    : ListView.builder(
                        itemCount: subs.length,
                        itemBuilder: (context, index) =>
                            _buildTile(context, subs[index]),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('添加订阅'),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rule_folder_outlined,
              size: 48, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            '暂无订阅',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '可添加 hosts / AdGuard 风格的规则地址',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, AdSubscription sub) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: Text(
                sub.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                sub.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Switch(
                value: sub.enabled,
                onChanged: (value) =>
                    AdRuleService.instance.setEnabled(sub.id, value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${sub.ruleCount} 条规则 · ${_formatTime(sub.lastUpdated)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: AdRuleService.instance.updating
                        ? null
                        : () async {
                            final service = AdRuleService.instance;
                            try {
                              await service.updateSubscription(sub.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('“${sub.name}”已更新')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('更新失败：$e')),
                              );
                            }
                          },
                    child: const Text('更新'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: '删除订阅',
                    onPressed: () => _confirmDelete(context, sub),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AdSubscription sub) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('确定要删除“${sub.name}”吗？本地规则缓存会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await AdRuleService.instance.removeSubscription(sub.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加订阅'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '规则地址',
                  hintText: 'https://example.com/rules.txt',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称（可选）',
                  hintText: '留空则使用域名',
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
                final url = urlController.text.trim();
                if (url.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                navigator.pop();
                final service = AdRuleService.instance;
                try {
                  await service.addSubscription(
                    nameController.text.trim(),
                    url,
                  );
                  messenger.showSnackBar(
                    const SnackBar(content: Text('订阅已添加并更新')),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('添加失败：$e')),
                  );
                }
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }
}
