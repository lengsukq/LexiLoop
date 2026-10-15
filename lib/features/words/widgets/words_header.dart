/// 词库页头部：标题、词条计数与三个添加入口。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/words/widgets/import_backup_button.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 词库页头部。
class WordsHeader extends StatelessWidget {
  /// 以当前筛选下的词条总数构造。
  const new({required this.total, super.key});

  /// 当前筛选命中的词条数；加载中为 `null`。
  final int? total;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s20,
        LexiSpace.s16,
        LexiSpace.s20,
        LexiSpace.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '单词本',
                  style: LexiType.page.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: LexiSpace.s4),
                Text(
                  total == null ? '加载中…' : '共 $total 个词条',
                  style: LexiType.body.copyWith(color: colors.secondaryLabel),
                ),
              ],
            ),
          ),
          const SizedBox(width: LexiSpace.s12),
          const Flexible(child: _HeaderActions()),
        ],
      ),
    );
  }
}

/// 头部右侧的三个入口。
///
/// 单独成控件而不是塞进 [WordsHeader.build]：守卫对 `build()` 有 80 行
/// 上限，而这三个入口还会随「快速添加」之类功能继续增加。
/// 用 `Wrap` 而不是 `Row`，窄窗口下按钮会自动折行而不是溢出。
class _HeaderActions extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: () => context.go(addWordPath),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('手动添加'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go(csvImportPath),
          icon: const Icon(Icons.upload_rounded, size: 17),
          label: const Text('CSV 导入'),
        ),
        const ImportBackupButton(),
      ],
    );
  }
}
