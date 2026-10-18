import 'package:flutter/material.dart';

import '../services/quick_engine_service.dart';

/// 快捷搜索引擎管理页（参考"移动端搜索引擎快捷切换"脚本的设置）
class QuickEnginesPage extends StatelessWidget {
  const QuickEnginesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = QuickEngineService.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷搜索引擎'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restore),
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final engines = service.engines;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: engines.length + 1,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              if (index == engines.length) {
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('添加自定义引擎'),
                  subtitle: const Text('名称 + 搜索地址，{q} 为关键字占位符'),
                  onTap: () => _showEngineDialog(context),
                );
              }
              final engine = engines[index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                title: Text(engine.name),
                subtitle: Text(
                  engine.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '上移',
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: index > 0
                          ? () => service.move(index, index - 1)
                          : null,
                    ),
                    IconButton(
                      tooltip: '下移',
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      onPressed: index < engines.length - 1
                          ? () => service.move(index, index + 1)
                          : null,
                    ),
                    IconButton(
                      tooltip: '编辑',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showEngineDialog(
                        context,
                        index: index,
                        initialName: engine.name,
                        initialUrl: engine.url,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final ok = await service.removeAt(index);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('至少需要保留一个引擎')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final service = QuickEngineService.instance;
    if (service.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已是默认引擎列表')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('将清空自定义引擎并恢复为默认列表，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.resetToDefault();
    }
  }

  Future<void> _showEngineDialog(
    BuildContext context, {
    int? index,
    String initialName = '',
    String initialUrl = '',
  }) async {
    final nameController = TextEditingController(text: initialName);
    final urlController = TextEditingController(text: initialUrl);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(index == null ? '添加引擎' : '编辑引擎'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入名称' : null,
              ),
              TextFormField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '搜索地址',
                  hintText: 'https://example.com/search?q={q}',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '请输入搜索地址' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final name = nameController.text;
    final url = urlController.text;
    nameController.dispose();
    urlController.dispose();
    if (result != true || name.trim().isEmpty || url.trim().isEmpty) return;
    final service = QuickEngineService.instance;
    if (index == null) {
      await service.add(name, url);
    } else {
      await service.update(index, name, url);
    }
  }
}
