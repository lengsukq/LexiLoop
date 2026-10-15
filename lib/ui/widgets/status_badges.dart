/// 状态徽章。
///
/// 旧版把状态标签的 map 在 3 处各写一遍（`initialize/page.tsx`、
/// `words/page.tsx`、`status-badges.tsx`）。这里集中一处。
///
/// 长相一律交给 `LexiBadge`：这里只负责「状态 → 文案 + 色调」的映射。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/widgets/badge.dart';

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
    final (String label, LexiBadgeTone tone) = switch (level) {
      MasteryLevel.newWord => ('新词', LexiBadgeTone.neutral),
      MasteryLevel.learning => ('学习中', LexiBadgeTone.warning),
      MasteryLevel.familiar => ('熟悉', LexiBadgeTone.accent),
      MasteryLevel.proficient => ('熟练', LexiBadgeTone.success),
      MasteryLevel.mastered => ('已掌握', LexiBadgeTone.purple),
    };

    return LexiBadge(
      label: score == null ? label : '$label · $score',
      tone: tone,
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
    // 「待初始化」与「已禁用」同属中性色：它们靠文案区分，不靠颜色。
    final (String label, LexiBadgeTone tone) = switch (status) {
      InitializationStatus.ready => ('已就绪', LexiBadgeTone.success),
      InitializationStatus.partial => ('部分就绪', LexiBadgeTone.warning),
      InitializationStatus.pending => ('待初始化', LexiBadgeTone.neutral),
      InitializationStatus.queued => ('排队中', LexiBadgeTone.accent),
      InitializationStatus.running => ('初始化中', LexiBadgeTone.accent),
      InitializationStatus.failed => ('失败', LexiBadgeTone.danger),
      InitializationStatus.disabled => ('已禁用', LexiBadgeTone.neutral),
    };

    return LexiBadge(label: label, tone: tone);
  }
}
