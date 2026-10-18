import 'package:flutter/material.dart';

import '../services/browser_data_service.dart';
import '../services/settings_service.dart';
import '../utils/url_utils.dart';
import 'quick_engines_page.dart';

/// 搜索设置页（参考 Via 设置-通用-搜索设置）
class SearchSettingsPage extends StatelessWidget {
  const SearchSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索设置')),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return ListView(
            children: [
              _sectionHeader(context, '搜索引擎'),
              _searchEngineTile(context, settings),
              if (settings.searchEngine == 'custom')
                _customSearchUrlTile(context, settings),
              _quickWordTile(context, settings),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('快捷搜索引擎'),
                subtitle: const Text('管理搜索结果页底部工具栏中的引擎'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const QuickEnginesPage(),
                    ),
                  );
                },
              ),
              const Divider(),

              _sectionHeader(context, '搜索建议'),
              SwitchListTile(
                secondary: const Icon(Icons.lightbulb_outline),
                title: const Text('搜索建议'),
                subtitle: const Text('输入时从搜索引擎获取建议'),
                value: settings.searchSuggestions,
                onChanged: settings.setSearchSuggestions,
              ),
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('建议来源'),
                subtitle: Text(_suggestSourcesLabel(settings)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSuggestSourcesDialog(context, settings),
              ),
              const Divider(),

              _sectionHeader(context, '搜索历史'),
              SwitchListTile(
                secondary: const Icon(Icons.history),
                title: const Text('记录搜索历史'),
                subtitle: const Text('在地址栏建议中显示此设备上的搜索'),
                value: settings.searchHistoryEnabled,
                onChanged: settings.setSearchHistoryEnabled,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清除搜索历史'),
                onTap: () => _confirmClearSearchHistory(context),
              ),
              const Divider(),

              _sectionHeader(context, '搜索框'),
              ListTile(
                leading: const Icon(Icons.crop_square),
                title: const Text('搜索框样式'),
                subtitle: Text(
                  settings.searchBoxStyle == 'rect' ? '矩形' : '线条',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSearchBoxStyleDialog(context, settings),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.blur_on),
                title: const Text('搜索框效果'),
                subtitle: const Text('地址栏背景模糊'),
                value: settings.searchBoxBlur,
                onChanged: settings.setSearchBoxBlur,
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('地址栏内容'),
                subtitle: Text(_addressBarContentLabel(settings)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAddressBarContentDialog(context, settings),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---- 搜索引擎 ----

  Widget _searchEngineTile(
      BuildContext context, SettingsService settings) {
    final label = settings.searchEngine == 'custom'
        ? '自定义'
        : SearchEngine.byKey(settings.searchEngine).label;
    return ListTile(
      leading: const Icon(Icons.search),
      title: const Text('搜索引擎'),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSearchEngineDialog(context, settings),
    );
  }

  void _showSearchEngineDialog(
      BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('搜索引擎'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...SearchEngine.builtin.map(
                  (engine) => _choiceTile(
                    dialogContext,
                    title: engine.label,
                    selected: settings.searchEngine == engine.key,
                    onTap: () {
                      settings.setSearchEngine(engine.key);
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
                _choiceTile(
                  dialogContext,
                  title: '自定义',
                  selected: settings.searchEngine == 'custom',
                  onTap: () {
                    settings.setSearchEngine(
                      'custom',
                      customUrl: settings.customSearchUrl,
                    );
                    Navigator.pop(dialogContext);
                    _showCustomSearchDialog(context, settings);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomSearchDialog(
      BuildContext context, SettingsService settings) {
    final controller =
        TextEditingController(text: settings.customSearchUrl);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('自定义搜索引擎'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '搜索地址',
              hintText: 'https://example.com/s?q={query}',
              helperText: '使用 {query} 作为关键字占位符',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final url = controller.text.trim();
                if (url.contains('{query}')) {
                  settings.setSearchEngine('custom', customUrl: url);
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Widget _customSearchUrlTile(
      BuildContext context, SettingsService settings) {
    return ListTile(
      leading: const Icon(Icons.link),
      title: const Text('自定义搜索地址'),
      subtitle: Text(
        settings.customSearchUrl.isEmpty ? '未设置' : settings.customSearchUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showCustomSearchDialog(context, settings),
    );
  }

  Widget _quickWordTile(BuildContext context, SettingsService settings) {
    final engineKey = settings.searchEngine;
    final engineLabel = engineKey == 'custom'
        ? '自定义'
        : SearchEngine.byKey(engineKey).label;
    final word = settings.searchQuickWords[engineKey] ?? '';
    return ListTile(
      leading: const Icon(Icons.flash_on_outlined),
      title: const Text('搜索快捷词'),
      subtitle: Text(word.isEmpty ? '未设置（$engineLabel）' : '$word（$engineLabel）'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showQuickWordDialog(context, settings),
    );
  }

  void _showQuickWordDialog(
      BuildContext context, SettingsService settings) {
    final engineKey = settings.searchEngine;
    final controller = TextEditingController(
      text: settings.searchQuickWords[engineKey] ?? '',
    );
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('搜索快捷词'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '快捷词',
                  hintText: '例如：g',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '输入“快捷词 + 空格 + 搜索内容”即可使用此引擎搜索，'
                '例如“g Via”。快捷词支持最多 16 个不含空格的字符，留空则禁用。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final word = controller.text.trim();
                if (word.contains(' ') || word.length > 16) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('快捷词无效')),
                  );
                  return;
                }
                // 同一快捷词只能被一个引擎使用
                final owner = settings.searchQuickWords.entries
                    .where((e) => e.value == word && e.key != engineKey)
                    .isEmpty;
                if (word.isNotEmpty && !owner) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('该快捷词已被使用')),
                  );
                  return;
                }
                settings.setSearchQuickWord(engineKey, word);
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ---- 建议来源 ----

  String _suggestSourcesLabel(SettingsService settings) {
    final parts = <String>[
      if (settings.suggestFromSearchEngine) '搜索引擎',
      if (settings.suggestFromHistory) '历史记录',
      if (settings.suggestFromBookmarks) '书签',
    ];
    return parts.isEmpty ? '无' : parts.join('、');
  }

  void _showSuggestSourcesDialog(
      BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void toggle(VoidCallback onChanged) {
              setDialogState(onChanged);
            }

            return AlertDialog(
              title: const Text('建议来源'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: settings.suggestFromSearchEngine,
                    title: const Text('搜索引擎'),
                    onChanged: (v) => toggle(
                      () => settings.setSuggestFromSearchEngine(v ?? false),
                    ),
                  ),
                  CheckboxListTile(
                    value: settings.suggestFromHistory,
                    title: const Text('历史记录'),
                    onChanged: (v) => toggle(
                      () => settings.setSuggestFromHistory(v ?? false),
                    ),
                  ),
                  CheckboxListTile(
                    value: settings.suggestFromBookmarks,
                    title: const Text('书签'),
                    onChanged: (v) => toggle(
                      () => settings.setSuggestFromBookmarks(v ?? false),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---- 搜索历史 ----

  Future<void> _confirmClearSearchHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除搜索历史'),
        content: const Text('你确认清除搜索历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BrowserDataService.instance.clearSearchHistory();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('搜索历史已清除')),
    );
  }

  // ---- 搜索框 ----

  void _showSearchBoxStyleDialog(
      BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('搜索框样式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choiceTile(
                dialogContext,
                title: '线条',
                selected: settings.searchBoxStyle != 'rect',
                onTap: () {
                  settings.setSearchBoxStyle('line');
                  Navigator.pop(dialogContext);
                },
              ),
              _choiceTile(
                dialogContext,
                title: '矩形',
                selected: settings.searchBoxStyle == 'rect',
                onTap: () {
                  settings.setSearchBoxStyle('rect');
                  Navigator.pop(dialogContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _addressBarContentLabel(SettingsService settings) {
    return switch (settings.addressBarContent) {
      'domain' => '域名',
      'title' => '标题',
      _ => '网址',
    };
  }

  void _showAddressBarContentDialog(
      BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('地址栏内容'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choiceTile(
                dialogContext,
                title: '网址',
                selected: settings.addressBarContent == 'url',
                onTap: () {
                  settings.setAddressBarContent('url');
                  Navigator.pop(dialogContext);
                },
              ),
              _choiceTile(
                dialogContext,
                title: '域名',
                selected: settings.addressBarContent == 'domain',
                onTap: () {
                  settings.setAddressBarContent('domain');
                  Navigator.pop(dialogContext);
                },
              ),
              _choiceTile(
                dialogContext,
                title: '标题',
                selected: settings.addressBarContent == 'title',
                onTap: () {
                  settings.setAddressBarContent('title');
                  Navigator.pop(dialogContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _choiceTile(
    BuildContext context, {
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(title),
      trailing: selected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
