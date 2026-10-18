/// 文章导入界面的公共基元。
///
/// 这些小组件在「粘贴 / 分段进度 / 预览 / 结果」四个步骤里反复出现；
/// 旧版 `article-tab.tsx` 把 `Metric` 与各类徽章内联在 1115 行的组件里，
/// 拆出来之后每一步的 `build()` 才可能落在 80 行以内。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/inline_notice.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 界面里展示的示例文章（旧版 `article-tab.tsx` 的 `SAMPLE_ARTICLE`）。
const String articleSampleArticle =
    'The rapid advancement of artificial intelligence has profoundly reshaped '
    'how we acquire knowledge. While conventional rote memorization emphasizes '
    'repetition, contemporary cognitive science suggests that contextual '
    'learning—encountering vocabulary within authentic discourse—yields more '
    'durable retention. Nevertheless, learners often feel overwhelmed when '
    'faced with an entire article replete with unfamiliar terminology. '
    'An intelligent system that discerns which words merit attention, based on '
    "the learner's existing lexicon, can transform a daunting passage into a "
    'curated learning experience.';

/// 卡片间距。
const double articleCardGap = 12;

/// 卡片内边距。
const double articleCardPadding = 14;

/// 小组件间距。
const double articleTightGap = 6;

/// 列表最大高度（分段与候选列表都要滚动，不能让整页无限长）。
const double articleListMaxHeight = 320;

/// 词条类型的中文名。
String articleEntryTypeLabel(LexicalContentType type) => switch (type) {
  LexicalContentType.word => '单词',
  LexicalContentType.phrase => '短语',
  LexicalContentType.sentence => '句子',
};

/// 预览有效期的 `HH:mm` 文本。
///
/// 不用 `intl` 的 `DateFormat`：这里只需要「几点几分」，而 `DateFormat` 需要
/// 装载 locale 数据，为一行提示引入初始化副作用不划算。
String articleExpiryText(int expiresAt) {
  final time = DateTime.fromMillisecondsSinceEpoch(expiresAt);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// 一块带标题的玻璃卡片。
///
/// 薄壳：文章流程的卡片比别处多一个「右侧计数」（`已选 3 / 12`），
/// 其余（内边距、标题样式、圆角）一律交给 [SectionCard]。
class ArticleSectionCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  /// 标题。
  final String title;

  /// 内容。
  final Widget child;

  /// 标题右侧的附加内容。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SectionCard(
    tone: LexiTone.sky,
    title: title,
    trailing: trailing,
    child: child,
  );
}

/// 一个统计指标。
class ArticleMetric extends StatelessWidget {
  /// 以标签、数值与配色构造。
  const new({required this.label, required this.value, this.color, super.key});

  /// 指标名。
  final String label;

  /// 指标值。
  final int value;

  /// 数值配色；为空时用主文字色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$value',
          style: LexiType.title2.copyWith(
            color: color ?? colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 一行指标（等宽分栏）。
class ArticleMetricRow extends StatelessWidget {
  /// 以指标列表构造。
  const new({required this.metrics, super.key});

  /// 指标。
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[for (final metric in metrics) Expanded(child: metric)],
  );
}

/// 错误横幅。
class ArticleErrorBanner extends StatelessWidget {
  /// 以文案构造。
  const new({required this.message, super.key});

  /// 文案。
  final String message;

  @override
  Widget build(BuildContext context) =>
      InlineNotice(key: const Key('articleErrorBanner'), message: message);
}

/// 提示横幅（AI 回退 / 未配置 AI）。
class ArticleNotice extends StatelessWidget {
  /// 以图标、文案与可选操作构造。
  const new({
    required this.icon,
    required this.message,
    this.action,
    this.tone,
    super.key,
  });

  /// 图标。
  final IconData icon;

  /// 文案。
  final String message;

  /// 可选操作按钮。
  final Widget? action;

  /// 主色；为空时用强调色。
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final color = tone ?? colors.accent;
    return Container(
      padding: const EdgeInsets.all(articleCardPadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: color.withValues(alpha: LexiTint.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              message,
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(width: LexiSpace.s8),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 状态徽章。
class ArticleBadge extends StatelessWidget {
  /// 以文案与色调构造。
  const new({required this.label, required this.tone, super.key});

  /// 文案。
  final String label;

  /// 语义色调。
  final LexiBadgeTone tone;

  @override
  Widget build(BuildContext context) => LexiBadge(label: label, tone: tone);
}
