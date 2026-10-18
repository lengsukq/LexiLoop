/// 词库页头部：标题、词条计数与三个添加入口。
///
/// 现在它只是一层「把这页的页头描述出来」的薄壳——真正的排版交给
/// `PageHeader`。保留这个类型有两个理由：词库页自己的测试按类型定位头部
/// （`find.byType(WordsHeader)`），而且「这一页的头部长什么样」在页面
/// 代码里读起来比一屏内联参数清楚。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/words/widgets/import_backup_button.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词库页头部。
class WordsHeader extends StatelessWidget {
  /// 以当前筛选下的词条总数构造。
  const new({required this.total, super.key});

  /// 当前筛选命中的词条数；加载中为 `null`。
  final int? total;

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      title: '单词本',
      // 计数保留在副标题里：它是这一页最常被扫一眼的数字。
      subtitle: total == null ? '加载中…' : '共 $total 个词条',
      actions: <PageHeaderAction>[
        PageHeaderAction(
          label: '手动添加',
          icon: LucideIcons.plus,
          // 加词是这一页的主线动作，给它填充底；导入是准备动作。
          primary: true,
          onPressed: () => context.go(addWordPath),
        ),
        PageHeaderAction(
          label: 'CSV 导入',
          icon: LucideIcons.upload,
          onPressed: () => context.go(csvImportPath),
        ),
      ],
      // 「导入备份」自带导入中状态（转圈），压不进纯动作，因此走 trailing。
      trailing: const ImportBackupButton(),
    );
  }
}
