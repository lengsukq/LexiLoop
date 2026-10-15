/// 文章导入的「分析中」界面：整体进度 + 逐批状态。
///
/// 对应旧版 `article-tab.tsx` 的 `step === "analyzing"` 分支。分批分析时
/// 每个批次一行：等待 / 请求中 / 成功 / 失败，失败与「AI 回退」都能单独重试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 分析中界面。
class ArticleProgressStep extends ConsumerWidget {
  /// 创建分析中界面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final segmented =
        state.analysis.useSegmented && state.analysis.segments.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ArticleSectionCard(
          title: segmented ? '正在分批分析…' : '正在分析文章并匹配你的词汇量…',
          child: _ProgressBody(segmented: segmented),
        ),
        if (segmented) ...<Widget>[
          const SizedBox(height: articleCardGap),
          const ArticleBatchListCard(),
        ],
      ],
    );
  }
}

class _ProgressBody extends ConsumerWidget {
  const new({required this.segmented});

  final bool segmented;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final progress = state.analysis.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(
              width: LexiSpace.s20,
              height: LexiSpace.s20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: LexiSpace.s10),
            Expanded(
              child: Text(
                segmented && progress != null
                    ? '${progress.done}/${progress.total} 批完成'
                    : '本地分词去重后，AI 会按你的水平筛选值得学的词 / 短语 / 句子',
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
            ),
          ],
        ),
        if (segmented && (progress?.failed ?? 0) > 0) ...<Widget>[
          const SizedBox(height: articleTightGap),
          Text(
            '${progress!.failed} 批失败，可在下方单独重试',
            style: LexiType.footnote.copyWith(color: colors.danger),
          ),
        ],
      ],
    );
  }
}

/// 分段进度卡（分析中与预览两步共用）。
class ArticleBatchListCard extends ConsumerWidget {
  /// 创建分段进度卡。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final plan = state.draft.plan;
    if (plan == null) return const SizedBox.shrink();
    final fallbackBatches = state.aiFallbackBatches;
    final failedBatches = state.failedBatches;
    return ArticleSectionCard(
      title:
          '分段进度 · ${state.successSegmentCount}/${state.analysis.segments.length} 段完成',
      trailing: Row(
        children: <Widget>[
          if (fallbackBatches.isNotEmpty)
            TextButton(
              key: const Key('articleRetryAiFallback'),
              onPressed: notifier.retryAiFallbackBatches,
              child: Text('重试 AI 回退（${fallbackBatches.length}）'),
            ),
          if (failedBatches.isNotEmpty)
            TextButton(
              key: const Key('articleRetryFailed'),
              onPressed: notifier.retryFailedBatches,
              child: Text('重试失败（${failedBatches.length}）'),
            ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: articleListMaxHeight),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final batch in plan.batches)
              _BatchRow(batch: batch, notifier: notifier),
          ],
        ),
      ),
    );
  }
}

class _BatchRow extends ConsumerWidget {
  const new({required this.batch, required this.notifier});

  final ArticleBatch batch;
  final ArticleWizardNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final segments = <ArticleSegmentState>[
      for (final segment in state.analysis.segments)
        if (batch.segmentIds.contains(segment.id)) segment,
    ];
    if (segments.isEmpty) return const SizedBox.shrink();
    final loading = segments.any(
      (segment) => segment.status == ArticleSegmentStatus.loading,
    );
    final isError = segments.any(
      (segment) => segment.status == ArticleSegmentStatus.error,
    );
    final isSuccess =
        !isError &&
        !loading &&
        segments.every(
          (segment) => segment.status == ArticleSegmentStatus.success,
        );
    final aiError = segments
        .map((segment) => segment.preview?.aiError)
        .whereType<String>()
        .firstOrNull;
    return Container(
      key: Key('articleBatchRow${batch.batchIndex}'),
      margin: const EdgeInsets.only(bottom: articleTightGap),
      padding: const EdgeInsets.all(LexiSpace.s10),
      decoration: BoxDecoration(
        color: isError ? colors.danger.withValues(alpha: 0.06) : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _BatchRowText(
              batch: batch,
              segments: segments,
              aiError: aiError,
            ),
          ),
          const SizedBox(width: LexiSpace.s8),
          _BatchStatusAction(
            batchIndex: batch.batchIndex,
            loading: loading,
            isError: isError,
            isSuccess: isSuccess,
            hasAiError: aiError != null,
            notifier: notifier,
          ),
        ],
      ),
    );
  }
}

/// 批次行的文字部分：标题、片段、失败原因与 AI 回退原因。
class _BatchRowText extends StatelessWidget {
  const new({
    required this.batch,
    required this.segments,
    required this.aiError,
  });

  final ArticleBatch batch;
  final List<ArticleSegmentState> segments;
  final String? aiError;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final failed = segments.firstWhere(
      (segment) => segment.status == ArticleSegmentStatus.error,
      orElse: () => segments.first,
    );
    final isError = failed.status == ArticleSegmentStatus.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '第 ${batch.batchIndex + 1} 批 · ${segments.length} 段 · '
          '${batch.charCount} 字符${aiError != null ? ' · AI 回退' : ''}',
          style: LexiType.footnote.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          segments.map((segment) => segment.previewText).join(' ｜ '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
        if (isError)
          Text(
            failed.error ?? '分析失败',
            style: LexiType.caption.copyWith(color: colors.danger),
          ),
        if (aiError != null)
          Text(
            aiError!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: LexiType.caption.copyWith(color: colors.warning),
          ),
      ],
    );
  }
}

class _BatchStatusAction extends StatelessWidget {
  const new({
    required this.batchIndex,
    required this.loading,
    required this.isError,
    required this.isSuccess,
    required this.hasAiError,
    required this.notifier,
  });

  final int batchIndex;
  final bool loading;
  final bool isError;
  final bool isSuccess;
  final bool hasAiError;
  final ArticleWizardNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    if (loading) {
      return const SizedBox(
        width: LexiSpace.s16,
        height: LexiSpace.s16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (isError) {
      return TextButton(
        key: Key('articleRetryBatch$batchIndex'),
        onPressed: () => notifier.retryBatch(batchIndex),
        child: const Text('重试'),
      );
    }
    if (isSuccess && hasAiError) {
      return TextButton(
        key: Key('articleRetryBatchAi$batchIndex'),
        onPressed: () => notifier.retryBatch(batchIndex),
        child: const Text('重试 AI'),
      );
    }
    if (isSuccess) {
      return Icon(Icons.check_circle_rounded, size: 16, color: colors.success);
    }
    return Text(
      '等待中',
      style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
    );
  }
}
