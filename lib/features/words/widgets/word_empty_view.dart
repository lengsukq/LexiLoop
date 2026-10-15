/// 词库列表页的空状态。
///
/// 分两种文案：库里一个词条都没有时给「去导入」的下一步；
/// 有词条但被筛空了只提示「调整筛选」——这两种情况下按钮没有意义，
/// 给一个导入口反而会让人以为自己的词库空了。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/words/widgets/import_backup_button.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 词库列表页的空状态。
class WordEmptyView extends StatelessWidget {
  /// 以「是否已被筛选条件筛空」构造。
  const new({required this.filtered, super.key});

  /// 当前是否有生效中的关键词或筛选条件。
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.menu_book_rounded,
              size: 44,
              color: context.lexiColors.tertiaryLabel,
            ),
            const SizedBox(height: 14),
            Text(
              filtered ? '没有匹配的词条' : '还没有词条',
              style: LexiType.title.copyWith(
                color: context.lexiColors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered ? '调整筛选条件或清空搜索词后再试。' : '可以导入旧版备份，也可以直接用 CSV 导入建立词库。',
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(
                color: context.lexiColors.secondaryLabel,
              ),
            ),
            if (!filtered) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const ImportBackupButton(),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => context.go(csvImportPath),
                    icon: const Icon(Icons.upload_rounded, size: 17),
                    label: const Text('CSV 导入'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
