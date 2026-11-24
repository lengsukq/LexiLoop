/// 文章导入的预览步骤：统计、AI 状态、分段进度与候选列表。
///
/// 对应旧版 `article-tab.tsx` 的 `step === "preview"` 分支。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_candidate_list.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/features/add/widgets/article_progress_step.dart';
import 'package:lexiloop/features/add/widgets/article_strategy_card.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 预览步骤。
class ArticlePreviewStep extends ConsumerWidget {
  /// 创建预览步骤。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final preview = state.preview;
    if (preview == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ArticleStrategyCard(),
        const SizedBox(height: articleCardGap),
        _SummaryCard(preview: preview),
        if (state.analysis.useSegmented &&
            state.analysis.segments.isNotEmpty) ...<Widget>[
          const SizedBox(height: articleCardGap),
          const ArticleBatchListCard(),
        ],
        const SizedBox(height: articleCardGap),
        const ArticleCandidateList(),
      ],
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  const new({required this.preview});

  final ArticleImportPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(articleWizardProvider.notifier);
    return ArticleSectionCard(
      title: preview.filename,
      trailing: Wrap(
        spacing: LexiSpace.s4,
        children: <Widget>[
          TextButton(
            key: const Key('articleBackToEdit'),
            onPressed: notifier.backToEdit,
            child: const Text('修改/重选难度'),
          ),
          TextButton(
            key: const Key('articleRestart'),
            onPressed: notifier.restart,
            child: const Text('重新粘贴'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ExpiryLine(preview: preview),
          const SizedBox(height: articleCardGap),
          _SummaryMetrics(preview: preview),
          const SizedBox(height: articleCardGap),
          _SummaryBadges(preview: preview),
          _SummaryNotices(preview: preview),
        ],
      ),
    );
  }
}

/// 有效期与分段规模提示。
class _ExpiryLine extends ConsumerWidget {
  const new({required this.preview});

  final ArticleImportPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final batches = state.draft.plan?.batches.length ?? 0;
    final segmented = state.analysis.useSegmented
        ? ' · 共 ${state.analysis.segments.length} 段分 $batches 批'
        : '';
    return Text(
      '预览在 ${articleExpiryText(preview.expiresAt)} 前有效$segmented',
      style: LexiType.footnote.copyWith(
        color: context.lexiColors.secondaryLabel,
      ),
    );
  }
}

/// 五个统计指标。
class _SummaryMetrics extends ConsumerWidget {
  const new({required this.preview});

  final ArticleImportPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final candidateCount = ref.watch(articleWizardProvider).candidateCount;
    return ArticleMetricRow(
      metrics: <Widget>[
        ArticleMetric(label: '全文词数', value: preview.articleStats.wordCount),
        ArticleMetric(label: '去重词数', value: preview.articleStats.uniqueCount),
        ArticleMetric(
          label: '待学候选',
          value: candidateCount,
          color: colors.success,
        ),
        ArticleMetric(
          label: '已掌握',
          value: preview.articleStats.knownCount,
          color: colors.accent,
        ),
        ArticleMetric(
          label: '短语/句子',
          value: preview.phraseCount + preview.sentenceCount,
          color: colors.purple,
        ),
      ],
    );
  }
}

/// AI 状态徽章。
class _SummaryBadges extends StatelessWidget {
  const new({required this.preview});

  final ArticleImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final phrases = preview.phraseCount > 0
        ? ' · 短语 ${preview.phraseCount}'
        : '';
    final sentences = preview.sentenceCount > 0
        ? ' · 句子 ${preview.sentenceCount}'
        : '';
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (preview.aiApplied)
          ArticleBadge(
            label:
                'AI 已筛选 · 推荐 ${preview.recommendedTerms.length} 词'
                '$phrases$sentences',
            tone: LexiBadgeTone.purple,
          )
        else
          const ArticleBadge(
            label: '未启用 AI · 展示单词与本地切句',
            tone: LexiBadgeTone.warning,
          ),
        ArticleBadge(
          label: '${preview.articleStats.charCount} 字符',
          tone: LexiBadgeTone.neutral,
        ),
      ],
    );
  }
}

/// AI 回退 / 未配置 AI 的提示。
class _SummaryNotices extends ConsumerWidget {
  const new({required this.preview});

  final ArticleImportPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final notifier = ref.read(articleWizardProvider.notifier);
    final aiError = preview.aiError;
    if (aiError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: articleCardGap),
        child: ArticleNotice(
          icon: LucideIcons.circleAlert,
          tone: colors.warning,
          message: '$aiError 已回退为展示单词与本地切句，你仍可手动勾选。',
          action: _AiRetryAction(notifier: notifier),
        ),
      );
    }
    if (preview.aiApplied) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: articleCardGap),
      child: ArticleNotice(
        icon: LucideIcons.wandSparkles,
        message: _configureAiHint,
        action: TextButton(
          key: const Key('articleConfigureAiLink'),
          onPressed: () =>
              GoRouter.maybeOf(context)?.go('$settingsPath?tab=ai'),
          child: const Text('去配置'),
        ),
      ),
    );
  }
}

/// 未配置 AI 时的引导文案。
final String _configureAiHint = <String>[
  '到「设置 → AI 模型」配置 LLM，',
  '即可按高考/四六级/雅思/托福等难度自动分词并还原词形；查词与发音仍由有道词典完成。',
].join();

/// AI 回退后的重试入口。
class _AiRetryAction extends ConsumerWidget {
  const new({required this.notifier});

  final ArticleWizardNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    if (!state.analysis.useSegmented) {
      return TextButton(
        key: const Key('articleRetryAi'),
        onPressed: notifier.analyzeSingle,
        child: const Text('重试 AI 筛选'),
      );
    }
    if (state.aiFallbackBatches.isEmpty) return const SizedBox.shrink();
    return TextButton(
      key: const Key('articleRetryAiFallbackInline'),
      onPressed: notifier.retryAiFallbackBatches,
      child: const Text('重试 AI 回退'),
    );
  }
}
