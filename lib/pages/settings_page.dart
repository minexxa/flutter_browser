import 'package:flutter/material.dart';

import '../pages/downloads_page.dart';
import '../services/browser_data_service.dart';
import '../services/settings_service.dart';
import '../utils/url_utils.dart';

/// 设置页（参考 Via 浏览器设置项）
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: AnimatedBuilder(
        animation: settings,
        builder: (context, _) {
          return ListView(
            children: [
              _sectionHeader(context, '通用'),
              _searchEngineTile(context, settings),
              _browserIdentityTile(context, settings),
              _fontSizeTile(context, settings),
              _homePageTile(context, settings),
              _switchTile(
                context,
                icon: Icons.restore,
                title: '启动时恢复未关闭的标签页',
                subtitle: '重新打开应用时还原上次的标签',
                value: settings.restoreTabs,
                onChanged: settings.setRestoreTabs,
              ),
              _switchTile(
                context,
                icon: Icons.volume_up_outlined,
                title: '使用音量键翻页',
                subtitle: '在网页中上下滚动页面',
                value: settings.volumeKeyScroll,
                onChanged: settings.setVolumeKeyScroll,
              ),
              const Divider(),

              _sectionHeader(context, '外观'),
              _themeModeTile(context, settings),
              _switchTile(
                context,
                icon: Icons.zoom_out_map,
                title: '强制缩放',
                subtitle: '允许对禁用缩放的网页进行缩放',
                value: settings.forceZoom,
                onChanged: settings.setForceZoom,
              ),
              _switchTile(
                context,
                icon: Icons.fullscreen,
                title: '全屏',
                subtitle: '隐藏系统状态栏',
                value: settings.fullscreen,
                onChanged: settings.setFullscreen,
              ),
              const Divider(),

              _sectionHeader(context, '网络'),
              _switchTile(
                context,
                icon: Icons.block_outlined,
                title: '广告拦截',
                subtitle: '内建规则仅拦截常见广告',
                value: settings.adBlock,
                onChanged: settings.setAdBlock,
              ),
              _switchTile(
                context,
                icon: Icons.image_outlined,
                title: '无图模式',
                subtitle: '不加载网页图片，节省流量',
                value: settings.noImage,
                onChanged: settings.setNoImage,
              ),
              _switchTile(
                context,
                icon: Icons.data_saver_on_outlined,
                title: '省流模式',
                subtitle: '隐藏图片与视频，禁止自动播放',
                value: settings.saveData,
                onChanged: settings.setSaveData,
              ),
              const Divider(),

              _sectionHeader(context, '隐私'),
              _switchTile(
                context,
                icon: Icons.password_outlined,
                title: '保存密码',
                subtitle: '保存网站登录使用的用户名和密码',
                value: settings.savePassword,
                onChanged: settings.setSavePassword,
              ),
              _switchTile(
                context,
                icon: Icons.content_paste_outlined,
                title: '允许网页访问剪贴板',
                value: settings.clipboardAccess,
                onChanged: settings.setClipboardAccess,
              ),
              _switchTile(
                context,
                icon: Icons.location_on_outlined,
                title: '允许网站访问地理位置',
                value: settings.geolocationAccess,
                onChanged: settings.setGeolocationAccess,
              ),
              _switchTile(
                context,
                icon: Icons.cleaning_services_outlined,
                title: '退出时清除数据',
                subtitle: '退出应用时清除浏览历史、缓存和网站数据',
                value: settings.clearOnExit,
                onChanged: settings.setClearOnExit,
              ),
              _clearDataTile(context),
              const Divider(),

              _sectionHeader(context, '下载'),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('下载位置'),
                subtitle: Text(_downloadPathLabel(settings.downloadPath)),
                onTap: () => _showDownloadPathDialog(context, settings),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载管理'),
                subtitle: const Text('查看和管理下载任务'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DownloadsPage(),
                    ),
                  );
                },
              ),
              const Divider(),

              _sectionHeader(context, '关于'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('版本'),
                subtitle: Text('1.0.0'),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  // ---- 通用 ----

  Widget _searchEngineTile(BuildContext context, SettingsService settings) {
    String label;
    if (settings.searchEngine == 'custom') {
      label = '自定义';
    } else {
      label = SearchEngine.byKey(settings.searchEngine).label;
    }
    return ListTile(
      leading: const Icon(Icons.search),
      title: const Text('搜索引擎'),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSearchEngineDialog(context, settings),
    );
  }

  void _showSearchEngineDialog(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('搜索引擎'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...SearchEngine.builtin.map((engine) {
                  return _choiceTile(
                    dialogContext,
                    title: engine.label,
                    selected: settings.searchEngine == engine.key,
                    onTap: () {
                      settings.setSearchEngine(engine.key);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
                _choiceTile(
                  dialogContext,
                  title: '自定义',
                  selected: settings.searchEngine == 'custom',
                  onTap: () {
                    settings.setSearchEngine('custom',
                        customUrl: settings.customSearchUrl);
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

  void _showCustomSearchDialog(BuildContext context, SettingsService settings) {
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

  Widget _browserIdentityTile(
      BuildContext context, SettingsService settings) {
    String label;
    if (settings.browserIdentity == 'custom') {
      label = '自定义';
    } else {
      label = BrowserIdentity.byKey(settings.browserIdentity).label;
    }
    return ListTile(
      leading: const Icon(Icons.devices_outlined),
      title: const Text('浏览器标识'),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showIdentityDialog(context, settings),
    );
  }

  void _showIdentityDialog(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('浏览器标识'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...BrowserIdentity.builtin.map((identity) {
                  return _choiceTile(
                    dialogContext,
                    title: identity.label,
                    selected: settings.browserIdentity == identity.key,
                    onTap: () {
                      settings.setBrowserIdentity(identity.key);
                      Navigator.pop(dialogContext);
                    },
                  );
                }),
                _choiceTile(
                  dialogContext,
                  title: '自定义',
                  selected: settings.browserIdentity == 'custom',
                  onTap: () {
                    settings.setBrowserIdentity('custom',
                        customUA: settings.customUserAgent);
                    Navigator.pop(dialogContext);
                    _showCustomUADialog(context, settings);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomUADialog(BuildContext context, SettingsService settings) {
    final controller = TextEditingController(text: settings.customUserAgent);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('自定义浏览器标识'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'User-Agent',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                settings.setBrowserIdentity(
                  'custom',
                  customUA: controller.text.trim(),
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Widget _fontSizeTile(BuildContext context, SettingsService settings) {
    return ListTile(
      leading: const Icon(Icons.format_size),
      title: const Text('字体大小'),
      subtitle: Text(FontSizeLevel.fromIndex(settings.fontSizeLevel).label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showFontSizeDialog(context, settings),
    );
  }

  void _showFontSizeDialog(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('字体大小'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < FontSizeLevel.values.length; i++)
                  _choiceTile(
                    dialogContext,
                    title: FontSizeLevel.values[i].label,
                    selected: settings.fontSizeLevel == i,
                    onTap: () {
                      settings.setFontSizeLevel(i);
                      Navigator.pop(dialogContext);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _homePageTile(BuildContext context, SettingsService settings) {
    final isDefault = settings.homePage == 'default';
    return ListTile(
      leading: const Icon(Icons.home_outlined),
      title: const Text('主页'),
      subtitle: Text(isDefault ? '默认主页' : settings.homePage),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showHomePageDialog(context, settings),
    );
  }

  void _showHomePageDialog(BuildContext context, SettingsService settings) {
    final isDefault = settings.homePage == 'default';
    final controller = TextEditingController(
      text: isDefault ? '' : settings.homePage,
    );
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('自定义主页'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '主页网址',
              hintText: '留空则使用默认主页',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                settings.setHomePage('default');
                Navigator.pop(dialogContext);
              },
              child: const Text('恢复默认'),
            ),
            FilledButton(
              onPressed: () {
                final url = controller.text.trim();
                settings.setHomePage(url.isEmpty ? 'default' : url);
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ---- 外观 ----

  Widget _themeModeTile(BuildContext context, SettingsService settings) {
    final label = switch (settings.themeMode) {
      AppThemeMode.system => '跟随系统',
      AppThemeMode.light => '亮色',
      AppThemeMode.dark => '深色',
    };
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('主题'),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemeModeDialog(context, settings),
    );
  }

  void _showThemeModeDialog(BuildContext context, SettingsService settings) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('主题'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choiceTile(
                dialogContext,
                title: '跟随系统',
                selected: settings.themeMode == AppThemeMode.system,
                onTap: () {
                  settings.setThemeMode(AppThemeMode.system);
                  Navigator.pop(dialogContext);
                },
              ),
              _choiceTile(
                dialogContext,
                title: '亮色',
                selected: settings.themeMode == AppThemeMode.light,
                onTap: () {
                  settings.setThemeMode(AppThemeMode.light);
                  Navigator.pop(dialogContext);
                },
              ),
              _choiceTile(
                dialogContext,
                title: '深色',
                selected: settings.themeMode == AppThemeMode.dark,
                onTap: () {
                  settings.setThemeMode(AppThemeMode.dark);
                  Navigator.pop(dialogContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 通用单选条目（带对勾指示）
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

  // ---- 隐私 ----

  Widget _clearDataTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: const Text('清除数据'),
      subtitle: const Text('缓存、Cookie、历史记录等'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showClearDataDialog(context),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    final checks = <String, bool>{
      '缓存': true,
      'Cookie': true,
      '历史记录': true,
      '网站数据': false,
    };
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('清除数据'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: checks.keys.map((key) {
                  return CheckboxListTile(
                    value: checks[key],
                    title: Text(key),
                    onChanged: (value) {
                      setDialogState(() => checks[key] = value ?? false);
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _doClearData(context, checks);
                  },
                  child: const Text('清除'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _doClearData(
    BuildContext context,
    Map<String, bool> checks,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (checks['历史记录'] == true) {
      await BrowserDataService.instance.clearHistory();
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('资料已清除')),
    );
  }

  // ---- 下载 ----

  String _downloadPathLabel(String path) {
    if (path == 'default') return '默认目录';
    return path;
  }

  void _showDownloadPathDialog(
      BuildContext context, SettingsService settings) {
    final controller = TextEditingController(
      text: settings.downloadPath == 'default' ? '' : settings.downloadPath,
    );
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('下载位置'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '目录路径',
              hintText: '留空则使用默认目录',
              helperText: '例如：/storage/emulated/0/Download',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                settings.setDownloadPath('default');
                Navigator.pop(dialogContext);
              },
              child: const Text('恢复默认'),
            ),
            FilledButton(
              onPressed: () {
                final path = controller.text.trim();
                settings.setDownloadPath(path.isEmpty ? 'default' : path);
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}
