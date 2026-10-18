/// 文章导入的完成步骤与「写入中」步骤。
///
/// 对应旧版 `article-tab.tsx` 的 `step === "committing"` 与
/// `step === "success"` 两个分支。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 完成摘要。
///
/// 用 `join()` 而不是相邻字符串字面量：中文文案之间不需要空格，而相邻字面量
/// 的「缺空格」会被 `missing_whitespace_between_adjacent_strings` 判为笔误。
String _successSummary(ArticleCommitResult result) => <String>[
  '新增 ${result.createdWords} 个，识别已有 ${result.existingWords} 个，',
  '新增内容补全任务 ${result.queuedInitializations} 个。',
].join();

/// 完成后的说明文案。
///
/// 用 `join()` 而不是相邻字符串字面量：中文文案之间不需要空格，而相邻字面量
/// 的「缺空格」会被 `missing_whitespace_between_adjacent_strings` 判为笔误。
final String _successHint = <String>[
  '新词条会由内容补全队列补齐释义、音标与例句；',
  '可在「内容补全」页查看进度。',
].join();

/// 写入中界面。
class ArticleCommittingStep extends StatelessWidget {
  /// 创建写入中界面。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ArticleSectionCard(
      title: '正在写入词库',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(
            width: LexiSpace.s24,
            height: LexiSpace.s24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: articleCardGap),
          Text(
            '创建内容补全任务并应用导入策略，请勿重复提交。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 完成界面。
class ArticleSuccessCard extends ConsumerWidget {
  /// 以提交结果构造。
  const new({required this.result, super.key});

  /// 提交结果。
  final ArticleCommitResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final notifier = ref.read(articleWizardProvider.notifier);
    return ArticleSectionCard(
      title: '导入完成',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LucideIcons.circleCheck, size: 34, color: colors.success),
          const SizedBox(height: articleCardGap),
          Text(
            _successSummary(result),
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: articleCardGap),
          Text(
            _successHint,
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
          const SizedBox(height: articleCardGap),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('articleRestartAfterSuccess'),
              onPressed: notifier.restart,
              child: const Text('继续导入'),
            ),
          ),
        ],
      ),
    );
  }
}
