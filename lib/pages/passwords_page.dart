import 'package:flutter/material.dart';

import '../services/browser_data_service.dart';

/// 已保存密码管理页（参考 Via 密码管理）
class PasswordsPage extends StatefulWidget {
  const PasswordsPage({super.key});

  @override
  State<PasswordsPage> createState() => _PasswordsPageState();
}

class _PasswordsPageState extends State<PasswordsPage> {
  Map<String, Map<String, String>> _passwords = {};
  Set<String> _neverSaveHosts = {};
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final map = await BrowserDataService.instance.savedPasswords();
    final never = await BrowserDataService.instance.neverSaveHosts();
    if (!mounted) return;
    setState(() {
      _passwords = map;
      _neverSaveHosts = never;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hosts = _passwords.keys.toList()..sort();
    final neverHosts = _neverSaveHosts.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清除全部',
            onPressed: hosts.isEmpty ? null : _confirmClearAll,
          ),
        ],
      ),
      body: hosts.isEmpty && neverHosts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.password_outlined,
                      size: 48, color: theme.colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    '暂无保存的密码',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              children: [
                if (hosts.isNotEmpty)
                  ...hosts.map(_buildPasswordTile),
                if (neverHosts.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '永不保存的网站',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ...neverHosts.map(_buildNeverSaveTile),
                ],
              ],
            ),
    );
  }

  Widget _buildPasswordTile(String host) {
    final entry = _passwords[host]!;
    final revealed = _revealed.contains(host);
    return ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(host),
      subtitle: Text(
        '${entry['username'] ?? ''}  ·  '
        '${revealed ? entry['password'] ?? '' : '••••••'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            tooltip: revealed ? '隐藏密码' : '显示密码',
            onPressed: () {
              setState(() {
                if (revealed) {
                  _revealed.remove(host);
                } else {
                  _revealed.add(host);
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '删除',
            onPressed: () async {
              await BrowserDataService.instance.removePassword(host);
              _revealed.remove(host);
              await _reload();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNeverSaveTile(String host) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.block, color: theme.colorScheme.outline),
      title: Text(host),
      subtitle: const Text('不再询问保存密码'),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: '移出（恢复询问）',
        onPressed: () async {
          await BrowserDataService.instance.removeNeverSaveHost(host);
          await _reload();
        },
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除密码'),
        content: const Text('确定要清除全部已保存的密码吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await BrowserDataService.instance.clearPasswords();
              _revealed.clear();
              await _reload();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
