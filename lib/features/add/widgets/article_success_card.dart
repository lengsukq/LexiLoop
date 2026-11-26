/// 文章导入的完成步骤与「写入中」步骤。
///
/// 对应旧版 `article-tab.tsx` 的 `step === "committing"` 与
/// `step === "success"` 两个分支。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 完成摘要。
String _successSummary(ArticleCommitResult result) => <String>[
  '新增 ${result.createdWords} 个，识别已有 ${result.existingWords} 个，',
  '新增内容补全任务 ${result.queuedInitializations} 个。',
].join();

/// 完成后的说明文案。
final String _successHint = <String>[
  '新词条正在通过有道词典接口自动补齐释义、音标与例句；',
  '可立即查看进度或直接打开单词本。',
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
            '创建有道查词补全任务并应用导入策略，请勿重复提交。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 完成界面：展示本批实时有道查词进度并提供直达入口。
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
          const SizedBox(height: articleTightGap),
          Text(
            _successHint,
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
          if (result.affectedWordIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: articleCardGap),
            _BatchLookupProgressCard(wordIds: result.affectedWordIds),
          ],
          const SizedBox(height: LexiSpace.s16),
          Wrap(
            spacing: LexiSpace.s8,
            runSpacing: LexiSpace.s8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('articleGoWords'),
                onPressed: () => GoRouter.maybeOf(context)?.go(wordsPath),
                icon: const Icon(LucideIcons.bookOpen, size: 16),
                label: const Text('去单词本'),
              ),
              OutlinedButton.icon(
                key: const Key('articleGoInitialize'),
                onPressed: () => GoRouter.maybeOf(context)?.go(initializePath),
                icon: const Icon(LucideIcons.listChecks, size: 16),
                label: const Text('查看查词队列'),
              ),
              TextButton(
                key: const Key('articleRestartAfterSuccess'),
                onPressed: notifier.restart,
                child: const Text('继续导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatchLookupProgressCard extends ConsumerWidget {
  const new({required this.wordIds});

  final List<int> wordIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final idsKey = wordIds.join(',');
    final progress = ref.watch(articleBatchProgressProvider(idsKey)).value;
    if (progress == null || progress.total == 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(articleCardPadding),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _progressSummary(progress),
                  style: LexiType.footnote.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (progress.queuedOrRunning > 0)
                TextButton(
                  key: const Key('articlePumpNow'),
                  onPressed: () => unawaited(_pumpNow(ref, idsKey)),
                  child: const Text('立即拉取'),
                ),
            ],
          ),
          const SizedBox(height: articleTightGap),
          ClipRRect(
            borderRadius: BorderRadius.circular(LexiRadius.pill),
            child: LinearProgressIndicator(value: progress.ratio),
          ),
        ],
      ),
    );
  }

  Future<void> _pumpNow(WidgetRef ref, String idsKey) async {
    await ref.read(queueActionsProvider).processNow();
    ref.invalidate(articleBatchProgressProvider(idsKey));
  }
}

String _progressSummary(ArticleBatchLookupProgress progress) {
  final pending = progress.queuedOrRunning > 0
      ? ' · 队列中 ${progress.queuedOrRunning}'
      : '';
  final failed = progress.failed > 0 ? ' · 失败 ${progress.failed}' : '';
  return '有道查词进度：已完成 ${progress.ready} / ${progress.total}$pending$failed';
}
