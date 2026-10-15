/// 配对准备页：选预设 → 开始。
///
/// 对应旧版 `match/page.tsx` 的准备卡片（3 个预设 + 参数回显）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 配对准备页。
class MatchSetupView extends StatelessWidget {
  /// 以状态与回调构造。
  const new({
    required this.state,
    required this.onSelect,
    required this.onStart,
    super.key,
  });

  /// 准备阶段状态。
  final MatchSetup state;

  /// 选择预设。
  final ValueChanged<MatchPreset> onSelect;

  /// 开始。
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListView(
      children: <Widget>[
        Text(
          '限时词汇配对',
          style: LexiType.page.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        Text(
          '将英文和中文释义快速配对。活跃错词、近期忘记和模糊的词会优先出现。',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s16),
        for (final preset in matchPresets)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s8),
            child: _PresetCard(
              preset: preset,
              selected: state.preset.id == preset.id,
              onTap: state.loading ? null : () => onSelect(preset),
            ),
          ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          Container(
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(LexiRadius.md),
            ),
            padding: const EdgeInsets.all(LexiSpace.s12),
            child: Text(
              state.error!,
              style: LexiType.footnote.copyWith(color: colors.dangerDeep),
            ),
          ),
        ],
        const SizedBox(height: LexiSpace.s14),
        FilledButton(
          onPressed: state.loading ? null : onStart,
          child: Text(state.loading ? '正在组题…' : '开始配对'),
        ),
        const SizedBox(height: LexiSpace.s10),
        Text(
          '至少需要 4 个带释义且释义不重复的可学习词条。',
          textAlign: TextAlign.center,
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const new({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final MatchPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.subtle,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      child: Material(
        color: selected
            ? colors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LexiRadius.lg),
              border: Border.all(
                color: selected ? colors.accent : colors.borderSubtle,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s14,
              vertical: LexiSpace.s12,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        preset.name,
                        style: LexiType.callout.copyWith(
                          color: colors.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${preset.pairs} 组 · ${preset.seconds} 秒 · '
                        '${preset.description}',
                        style: LexiType.footnote.copyWith(
                          color: colors.quaternaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colors.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
