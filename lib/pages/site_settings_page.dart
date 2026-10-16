import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/site_settings.dart';
import '../services/site_settings_service.dart';
import 'shell_page.dart';

/// 网站设置页（参考 Via 网站设置：按站点覆盖 UA/JS/Cookie/图片/广告拦截）
class SiteSettingsPage extends StatefulWidget {
  const SiteSettingsPage({super.key, required this.host});

  final String host;

  @override
  State<SiteSettingsPage> createState() => _SiteSettingsPageState();
}

class _SiteSettingsPageState extends State<SiteSettingsPage> {
  static const MethodChannel _cookieChannel =
      MethodChannel('com.example.flutter_android_browser/cookies');

  late SiteSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = SiteSettingsService.instance.editableFor(widget.host);
  }

  Future<void> _updateAndSave(SiteSettings updated) async {
    setState(() => _settings = updated);
    await SiteSettingsService.instance.save(updated);
    // UA / JS 等变更需要重载当前页生效
    await shellPageKey.currentState?.applySiteSettingsAndReload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('网站设置'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.host,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          _sectionHeader(theme, '浏览器标识'),
          _uaTile(context),
          _sectionHeader(theme, '网页功能'),
          _jsTile(context),
          _cookieTile(context),
          _imageTile(context),
          _sectionHeader(theme, '广告拦截'),
          _adBlockTile(context),
          const Divider(),
          _clearSiteDataTile(context),
          _resetTile(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
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

  // ---- 浏览器标识 ----

  String get _uaLabel {
    final ua = _settings.userAgent;
    if (ua == null) return '跟随全局';
    if (ua == 'desktop') return '桌面版网站';
    if (ua == 'mobile') return '移动版网站';
    return '自定义';
  }

  Widget _uaTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.devices_outlined),
      title: const Text('浏览器标识'),
      subtitle: Text(_uaLabel),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showUaDialog(context),
    );
  }

  void _showUaDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('浏览器标识'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _choiceTile(dialogContext, '跟随全局', _settings.userAgent == null,
                    () {
                  Navigator.pop(dialogContext);
                  _updateAndSave(_settings.copyWith(userAgent: null));
                }),
                _choiceTile(dialogContext, '桌面版网站',
                    _settings.userAgent == 'desktop', () {
                  Navigator.pop(dialogContext);
                  _updateAndSave(
                      _settings.copyWith(userAgent: 'desktop'));
                }),
                _choiceTile(dialogContext, '移动版网站',
                    _settings.userAgent == 'mobile', () {
                  Navigator.pop(dialogContext);
                  _updateAndSave(_settings.copyWith(userAgent: 'mobile'));
                }),
                _choiceTile(
                    dialogContext,
                    '自定义',
                    _settings.userAgent != null &&
                        _settings.userAgent != 'desktop' &&
                        _settings.userAgent != 'mobile', () {
                  Navigator.pop(dialogContext);
                  _showCustomUaDialog(context);
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomUaDialog(BuildContext context) {
    final controller = TextEditingController(text: _settings.userAgent ?? '');
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('自定义浏览器标识'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'User-Agent'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                final ua = controller.text.trim();
                if (ua.isNotEmpty) {
                  _updateAndSave(_settings.copyWith(userAgent: ua));
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ---- 三态开关 ----

  Widget _tristateTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool? value,
    required String trueLabel,
    required String falseLabel,
    required ValueChanged<bool?> onChanged,
  }) {
    final label = value == null
        ? '跟随全局'
        : value
            ? trueLabel
            : falseLabel;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _choiceTile(dialogContext, '跟随全局', value == null,
                      () {
                    Navigator.pop(dialogContext);
                    onChanged(null);
                  }),
                  _choiceTile(dialogContext, trueLabel, value == true,
                      () {
                    Navigator.pop(dialogContext);
                    onChanged(true);
                  }),
                  _choiceTile(dialogContext, falseLabel, value == false,
                      () {
                    Navigator.pop(dialogContext);
                    onChanged(false);
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _jsTile(BuildContext context) {
    return _tristateTile(
      context,
      icon: Icons.javascript_outlined,
      title: 'JavaScript',
      value: _settings.javaScript,
      trueLabel: '启用',
      falseLabel: '禁用',
      onChanged: (value) =>
          _updateAndSave(_settings.copyWith(javaScript: value)),
    );
  }

  Widget _cookieTile(BuildContext context) {
    return _tristateTile(
      context,
      icon: Icons.cookie_outlined,
      title: 'Cookie',
      value: _settings.cookies,
      trueLabel: '允许',
      falseLabel: '禁止',
      onChanged: (value) =>
          _updateAndSave(_settings.copyWith(cookies: value)),
    );
  }

  Widget _imageTile(BuildContext context) {
    return _tristateTile(
      context,
      icon: Icons.image_outlined,
      title: '图片',
      value: _settings.images,
      trueLabel: '允许',
      falseLabel: '阻止',
      onChanged: (value) =>
          _updateAndSave(_settings.copyWith(images: value)),
    );
  }

  Widget _adBlockTile(BuildContext context) {
    return _tristateTile(
      context,
      icon: Icons.block_outlined,
      title: '广告拦截',
      value: _settings.adBlock,
      trueLabel: '启用',
      falseLabel: '禁用',
      onChanged: (value) =>
          _updateAndSave(_settings.copyWith(adBlock: value)),
    );
  }

  // ---- 数据清理 ----

  Widget _clearSiteDataTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: const Text('清除此站点的数据'),
      subtitle: const Text('清除该站点保存的 Cookie'),
      onTap: () async {
        try {
          await _cookieChannel.invokeMethod(
            'clearCookiesForHost',
            widget.host,
          );
        } catch (_) {}
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除该站点的 Cookie')),
        );
      },
    );
  }

  Widget _resetTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.restore),
      title: const Text('重置此站点设置'),
      subtitle: const Text('全部恢复为跟随全局'),
      onTap: () async {
        await SiteSettingsService.instance.remove(widget.host);
        if (!context.mounted) return;
        setState(() => _settings = SiteSettings(host: widget.host));
        await shellPageKey.currentState?.applySiteSettingsAndReload();
      },
    );
  }

  Widget _choiceTile(
    BuildContext context,
    String title,
    bool selected,
    VoidCallback onTap,
  ) {
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
