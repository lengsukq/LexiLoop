/// 首页「今日建议」卡片。
///
/// 对应旧版 `app/(main)/daily-ai-suggestion.tsx`。
///
/// **降级是常态而非异常**：没有配置 AI 时由规则式生成建议，
/// 界面不区分「AI 生成」与「规则生成」的视觉层级——对用户来说
/// 两者都是「今天的建议」，只有来源标签不同。AI 生成失败时也照常
/// 展示规则式结果，只附一行说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/services/suggestion_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

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
    return DashboardCard(
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
          style: TextStyle(color: context.lexiColors.danger, fontSize: 12.5),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                suggestion.headline,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SourceBadge(suggestion: suggestion),
          ],
        ),
        if (suggestion.summary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            suggestion.summary,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
          ),
        ],
        if (suggestion.actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          for (final action in suggestion.actions)
            _Bullet(text: action, color: colors.accent),
        ],
        if (suggestion.risks.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final risk in suggestion.risks)
            _Bullet(text: risk, color: colors.warning),
        ],
        if (suggestion.recommendedItems.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '推荐复习 ${suggestion.recommendedItems.length} 个词条',
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: chipGap,
            runSpacing: chipGap,
            children: <Widget>[
              for (final item in suggestion.recommendedItems.take(maxChips))
                _WordChip(item: item),
            ],
          ),
        ],
        if (suggestion.generationWarning != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            suggestion.generationWarning!,
            style: TextStyle(color: colors.warning, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 10),
        Align(
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
        ),
      ],
    );
  }
}

/// 来源标签：AI 或规则。
class _SourceBadge extends StatelessWidget {
  const new({required this.suggestion});

  final DailySuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final ai = suggestion.generator == SuggestionGenerator.ai;
    final tint = ai ? colors.purple : colors.tertiaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Text(
        ai ? 'AI 生成' : '规则生成',
        style: TextStyle(color: tint, fontSize: 11),
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
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: context.lexiColors.secondaryLabel,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 推荐词条芯片。
class _WordChip extends StatelessWidget {
  const new({required this.item});

  final RecommendedStudyItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Tooltip(
      message: item.reason.isEmpty ? item.term : item.reason,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
        child: Text(
          item.term,
          style: TextStyle(color: colors.label, fontSize: 12.5),
        ),
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
    style: TextStyle(color: context.lexiColors.tertiaryLabel, fontSize: 12.5),
  );
}

/// 芯片间距。
const double chipGap = 6;

/// 最多展示的推荐词条数。
const int maxChips = 8;

/// 指示器尺寸。
const double indicatorSize = 14;

/// 要点圆点尺寸。
const double dotSize = 4;
