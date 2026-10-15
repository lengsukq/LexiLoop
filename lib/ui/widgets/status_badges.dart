/// 状态徽章。
///
/// 旧版把状态标签的 map 在 3 处各写一遍（`initialize/page.tsx`、
/// `words/page.tsx`、`status-badges.tsx`）。这里集中一处。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 掌握等级徽章。
class MasteryBadge extends StatelessWidget {
  /// 以等级构造。
  const new({required this.level, this.score, super.key});

  /// 掌握等级。
  final MasteryLevel level;

  /// 掌握分，可选。
  final int? score;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (String label, Color color) = switch (level) {
      MasteryLevel.newWord => ('新词', colors.tertiaryLabel),
      MasteryLevel.learning => ('学习中', colors.warning),
      MasteryLevel.familiar => ('熟悉', colors.accent),
      MasteryLevel.proficient => ('熟练', colors.success),
      MasteryLevel.mastered => ('已掌握', colors.purple),
    };

    return _Badge(
      label: score == null ? label : '$label · $score',
      color: color,
    );
  }
}

/// 初始化状态徽章。
class InitializationBadge extends StatelessWidget {
  /// 以状态构造。
  const new({required this.status, super.key});

  /// 初始化状态。
  final InitializationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (String label, Color color) = switch (status) {
      InitializationStatus.ready => ('已就绪', colors.success),
      InitializationStatus.partial => ('部分就绪', colors.warning),
      InitializationStatus.pending => ('待初始化', colors.tertiaryLabel),
      InitializationStatus.queued => ('排队中', colors.accent),
      InitializationStatus.running => ('初始化中', colors.accent),
      InitializationStatus.failed => ('失败', colors.danger),
      InitializationStatus.disabled => ('已禁用', colors.quaternaryLabel),
    };

    return _Badge(label: label, color: color);
  }
}

class _Badge extends StatelessWidget {
  const new({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s8,
        vertical: LexiSpace.s2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        label,
        style: LexiType.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
