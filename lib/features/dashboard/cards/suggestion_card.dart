/// 首页「今日建议」卡片。
///
/// 对应旧版 `app/(main)/daily-ai-suggestion.tsx`。
///
/// **降级是常态而非异常**：没有配置 AI 时由规则式生成建议，
/// 界面不区分「AI 生成」与「规则生成」的视觉层级——对用户来说
/// 两者都是「今天的建议」，只有来源标签不同。AI 生成失败时也照常
/// 展示规则式结果，只附一行说明。
///
/// **质量分与推荐列表是一体的，不是装饰**：旧版把质量分做成一个圆环，
/// 把推荐词条做成两列卡片，并且给了一个直接跳进重点复习的入口；本版一度
/// 只留下「一句标题 + 一排词条芯片」，把已经算好的指标、推荐理由与入口
/// 全部丢掉，用户看完不知道「我昨天做得怎么样」「该先背哪几个」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/services/suggestion_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 「昨日质量」徽章文字的 Key，供测试定位（文字同时携带分数与语气色）。
const Key suggestionQualityTextKey = Key('suggestion-quality');

/// 「开始重点复习」按钮的 Key，供测试定位。
const Key focusReviewButtonKey = Key('suggestion-focus-review');

/// 今日建议卡片。
class SuggestionCard extends ConsumerStatefulWidget {
  /// 以键构造。
  const new({super.key});

  @override
  ConsumerState<SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<SuggestionCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final suggestion = ref.watch(dailySuggestionProvider);
    return SectionCard(
      title: '今日建议',
      icon: Icons.lightbulb_outline,
      child: suggestion.when(
        data: (data) => data == null
            ? const _EmptyHint()
            : _SuggestionBody(
                suggestion: data,
                busy: _busy,
                onRegenerate: _regenerate,
              ),
        loading: () => const DashboardLoading(),
        error: (error, _) => Text(
          '加载失败：$error',
          style: LexiType.footnote.copyWith(color: context.lexiColors.danger),
        ),
      ),
    );
  }

  /// 重新生成（用户主动触发，会走一次 AI 调用）。
  Future<void> _regenerate() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(dailySuggestionProvider.notifier).regenerate();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 建议正文。
///
/// 分区顺序沿用旧版的信息密度：先「结论 + 质量」，再「昨天发生了什么」，
/// 最后「今天该做什么」。亮点 / 风险 / 行动三条要点此前只渲染了后两条，
/// 亮点被整段丢弃——它由服务与 AI 都会填充，丢掉等于白算。
class _SuggestionBody extends StatelessWidget {
  const new({
    required this.suggestion,
    required this.busy,
    required this.onRegenerate,
  });

  final DailySuggestion suggestion;
  final bool busy;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final items = suggestion.recommendedItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SuggestionHeader(suggestion: suggestion),
        if (suggestion.summary.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          Text(
            suggestion.summary,
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ],
        const SizedBox(height: LexiSpace.s10),
        _MetricRow(metrics: suggestion.metrics),
        _BulletGroup(
          title: '亮点',
          items: suggestion.strengths,
          color: colors.success,
        ),
        _BulletGroup(
          title: '风险',
          items: suggestion.risks,
          color: colors.warning,
        ),
        _BulletGroup(
          title: '行动建议',
          items: suggestion.actions,
          color: colors.accent,
        ),
        if (items.isNotEmpty) _RecommendedSection(items: items),
        if (suggestion.generationWarning != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s8),
          Text(
            suggestion.generationWarning!,
            style: LexiType.caption.copyWith(color: colors.warning),
          ),
        ],
        _RegenerateButton(busy: busy, onRegenerate: onRegenerate),
      ],
    );
  }
}

/// 标题 + 来源标签 + 昨日质量徽章。
class _SuggestionHeader extends StatelessWidget {
  const new({required this.suggestion});

  final DailySuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            suggestion.headline,
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: LexiSpace.s6),
        _QualityBadge(score: suggestion.qualityScore),
        const SizedBox(width: LexiSpace.s6),
        _SourceBadge(ai: suggestion.generator == SuggestionGenerator.ai),
      ],
    );
  }
}

/// 昨日质量徽章：分数越高颜色越「好」。
///
/// **没有分数时用中性灰而不是红色**：质量分为空意味着昨天根本没有作答记录，
/// 染成红色会读成「昨天表现很差」，与事实相反（旧版用 `slate` 表达同一件事）。
class _QualityBadge extends StatelessWidget {
  const new({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final tone = qualityTone(context.lexiColors, score);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s8,
        vertical: LexiSpace.s2,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Text(
        score == null ? '昨日质量 无记录' : '昨日质量 $score',
        key: suggestionQualityTextKey,
        style: LexiType.caption.copyWith(color: tone),
      ),
    );
  }
}

/// 来源标签：AI 或规则。
class _SourceBadge extends StatelessWidget {
  const new({required this.ai});

  final bool ai;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tint = ai ? colors.purple : colors.tertiaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s8,
        vertical: LexiSpace.s2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Text(
        ai ? 'AI 生成' : '规则生成',
        style: LexiType.caption.copyWith(color: tint),
      ),
    );
  }
}

/// 昨日的四项关键指标：作答 / 正确率 / 跳过 / 分钟。
///
/// 四项都来自 [DailySuggestionMetrics]，此前一个都没渲染；正确率在昨天
/// 没有作答时是 `null`，显示破折号而不是 `0%`——同样是「没数据」，
/// `0%` 会被读成「昨天全错了」。
class _MetricRow extends StatelessWidget {
  const new({required this.metrics});

  final DailySuggestionMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final accuracy = metrics.accuracy;
    return Row(
      children: <Widget>[
        Expanded(
          child: _MetricTile(
            label: '作答',
            value: '${metrics.reviewCount}',
            metric: 'answers',
          ),
        ),
        Expanded(
          child: _MetricTile(
            label: '正确率',
            value: accuracy == null ? '—' : '$accuracy%',
            metric: 'accuracy',
          ),
        ),
        Expanded(
          child: _MetricTile(
            label: '跳过',
            value: '${metrics.skippedCount}',
            metric: 'skipped',
          ),
        ),
        Expanded(
          child: _MetricTile(
            label: '分钟',
            value: '${metrics.studyMinutes}',
            metric: 'minutes',
          ),
        ),
      ],
    );
  }
}

/// 单个指标格。
class _MetricTile extends StatelessWidget {
  const new({required this.label, required this.value, required this.metric});

  final String label;
  final String value;
  final String metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: LexiSpace.s4),
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s8),
      decoration: BoxDecoration(
        color: colors.fill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            key: Key('suggestion-metric-$metric'),
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s2),
          Text(
            label,
            style: LexiType.caption.copyWith(color: colors.quaternaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 一组带小标题的要点。
///
/// 三组要点共用一个组件而不是三份 `_Bullet` 循环：亮点 / 风险 / 行动建议
/// 的差别只有标题与颜色，展开写就是旧版基线里的「重复逻辑」。
class _BulletGroup extends StatelessWidget {
  const new({required this.title, required this.items, required this.color});

  final String title;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
          const SizedBox(height: LexiSpace.s6),
          for (final item in items) _Bullet(text: item, color: color),
        ],
      ),
    );
  }
}

/// 一条要点。
class _Bullet extends StatelessWidget {
  const new({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LexiSpace.s4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: LexiSpace.s6),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: LexiSpace.s8),
        Expanded(
          child: Text(
            text,
            style: LexiType.footnote.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 今日重点复习：推荐词条清单 + 进入重点复习的入口。
///
/// **没有推荐词条时整段不渲染**：入口指向 `/study?mode=AI_RECOMMENDED`，
/// 而该模式的候选池就是这些推荐词条；清单为空还摆一个按钮，点进去只会
/// 撞上一次空会话。
class _RecommendedSection extends StatelessWidget {
  const new({required this.items});

  final List<RecommendedStudyItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: LexiSpace.s12),
        Row(
          children: <Widget>[
            Text(
              '今日重点复习',
              style: LexiType.body.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${items.length} 题',
              style: LexiType.footnote.copyWith(color: colors.danger),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s8),
        for (final item in items) _RecommendedEntry(item: item),
        const SizedBox(height: LexiSpace.s8),
        const _FocusReviewButton(),
      ],
    );
  }
}

/// 一条推荐词条：词条 + 题型 + 释义 + 推荐理由。
///
/// **四项一起显示，而不是把理由塞进 Tooltip**：理由只在悬停时可见，
/// 移动端没有悬停，推荐理由等于不存在；词条与释义则让人一眼确认
/// 「要背的到底是哪个词」。
class _RecommendedEntry extends StatelessWidget {
  const new({required this.item});

  final RecommendedStudyItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final definition = item.definition;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.term,
                  style: LexiType.body.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: LexiSpace.s6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LexiSpace.s6,
                  vertical: LexiSpace.s2,
                ),
                decoration: BoxDecoration(
                  color: colors.fill,
                  borderRadius: BorderRadius.circular(LexiRadius.sm),
                ),
                child: Text(
                  questionTypeLabel(item.questionType),
                  style: LexiType.caption.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ),
            ],
          ),
          if (definition != null && definition.isNotEmpty)
            Text(
              definition,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
          if (item.reason.isNotEmpty)
            Text(
              item.reason,
              style: LexiType.caption.copyWith(color: colors.quaternaryLabel),
            ),
        ],
      ),
    );
  }
}

/// 「开始重点复习」入口。
class _FocusReviewButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: focusReviewButtonKey,
        onPressed: () => goToStudyMode(context, StudyMode.aiRecommended),
        icon: const Icon(Icons.psychology_alt_rounded, size: 18),
        label: const Text('开始重点复习'),
      ),
    );
  }
}

/// 「重新生成」入口。
class _RegenerateButton extends StatelessWidget {
  const new({required this.busy, required this.onRegenerate});

  final bool busy;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: busy ? null : onRegenerate,
        icon: busy
            ? const SizedBox(
                width: indicatorSize,
                height: indicatorSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 16),
        label: const Text('重新生成'),
      ),
    );
  }
}

/// 无建议时的提示。
class _EmptyHint extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Text(
    '今天还没有建议。积累一些复习记录后会更有针对性。',
    style: LexiType.footnote.copyWith(color: context.lexiColors.tertiaryLabel),
  );
}

/// 质量分的「好」阈值。
///
/// 与旧版 `scoreTone` 的 80/60 分档一致：80 以上绿色、60 以上琥珀、
/// 以下红色。
const int highQualityScore = 80;

/// 质量分的「一般」阈值；低于此值为红色。
const int mediumQualityScore = 60;

/// 质量分对应的语气色；[score] 为 `null`（昨天没有作答记录）时取中性灰。
Color qualityTone(LexiColors colors, int? score) {
  if (score == null) return colors.quaternaryLabel;
  if (score >= highQualityScore) return colors.success;
  if (score >= mediumQualityScore) return colors.warning;
  return colors.danger;
}

/// 要点圆点尺寸。
const double dotSize = 4;

/// 指示器尺寸。
const double indicatorSize = 14;
