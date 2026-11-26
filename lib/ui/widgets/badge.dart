/// 统一的徽章（badge / tag / chip 标签）。
///
/// **为什么需要它**：收敛前全应用有 16 处各自实现的徽章——底色透明度散在
/// `0.06 / 0.08 / 0.10 / 0.12 / 0.14 / 0.16` 六档，圆角在 `xs / sm` 之间摇摆，
/// 内边距有 `(8,2) / (8,4) / (10,4) / (12,8)` 四种，字号写法也不一致。
/// 它们单看都合理，摆在同一屏里就成了「长短各一截」。
///
/// 这里只保留两个**有语义差别**的变体：[LexiBadgeEmphasis.tint]（淡底）与
/// [LexiBadgeEmphasis.outline]（淡底 + 同色描边，用在淡底与卡片底分不开时）。
/// 其余差异一律取消——徽章不该有 16 种长相。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 徽章的语义色调。
enum LexiBadgeTone {
  /// 中性——状态未知、已禁用、无记录。
  neutral,

  /// 强调——进行中、当前项、AI 生成。
  accent,

  /// 成功——已就绪、已完成、目标达成。
  success,

  /// 警告——部分就绪、质量偏低。
  warning,

  /// 危险——失败、错误、重点复习。
  danger,

  /// 紫色——关系标签、辅助分类。
  purple,
}

/// 徽章的视觉变体。
enum LexiBadgeEmphasis {
  /// 淡色底、无描边（默认）。绝大多数场合用它。
  tint,

  /// 淡色底 + 同色描边。用在徽章与相邻底色（尤其是另一个淡色块）分不开时。
  outline,
}

/// 一枚徽章。
class LexiBadge extends StatelessWidget {
  /// 以文案与色调构造。
  const new({
    required this.label,
    this.tone = LexiBadgeTone.neutral,
    this.emphasis = LexiBadgeEmphasis.tint,
    super.key,
  });

  /// 徽章文案。
  final String label;

  /// 语义色调。
  final LexiBadgeTone tone;

  /// 视觉变体。
  final LexiBadgeEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    // 底色用饱和色（`accent`/`success`…），文字用**专供文字**的深色变体：
    // 饱和色当文字压在自家 12% 淡底上只有 2–3:1，读不清（见 LexiColors 的
    // `*Text` 一组）。
    final (Color fill, Color foreground) = switch (tone) {
      LexiBadgeTone.neutral => (colors.tertiaryLabel, colors.secondaryLabel),
      LexiBadgeTone.accent => (colors.accent, colors.accentText),
      LexiBadgeTone.success => (colors.success, colors.successText),
      LexiBadgeTone.warning => (colors.warning, colors.warningText),
      LexiBadgeTone.danger => (colors.danger, colors.dangerText),
      LexiBadgeTone.purple => (colors.purple, colors.purpleText),
    };

    // 底色**先合成成不透明色**，而不是直接交一个半透明色给 `Container`。
    //
    // 原因是深色模式的对比度：深色下 `accentText` 就是 `accent` 本身
    // （#0A84FF），它压在卡片底 #1C1C1E 上只有 4.6:1，已经贴着下限；再把
    // 12% 的同色淡底叠在卡片上，底被提亮，就掉到 4.09:1（danger 4.40、
    // purple 4.19）——徽章在深色下读不清。
    //
    // 合成到**页面底**（深色下是纯黑）而不是卡片底，底色反而比卡片更深，
    // 六种色调全部回到 5.2:1 以上；视觉上是一枚内嵌的深色胶囊。
    // 浅色模式合成到卡片底（白），与卡片融为一体。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? colors.surface : colors.card;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s8,
        vertical: LexiSpace.s4,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(fill.withValues(alpha: LexiTint.tint), base),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        border: emphasis == LexiBadgeEmphasis.outline
            ? Border.all(color: fill.withValues(alpha: LexiTint.border))
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LexiType.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
