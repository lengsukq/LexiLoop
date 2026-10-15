/// 词库列表里的一张词条卡片。
///
/// 卡片上只放「一眼能判断要不要点进去」的信息：词形、两条状态徽标、
/// 释义摘要、语向与到期日。编辑、复习记录这些留给详情页。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/features/words/words_format.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 词条卡片。
class WordCard extends StatelessWidget {
  /// 以词条与点击回调构造。
  const new({required this.entry, required this.onTap, super.key});

  /// 卡片对应的词条行。
  final WordListEntry entry;

  /// 进入词条详情。
  final VoidCallback onTap;

  /// 复习卡是否已到期。
  ///
  /// 在界面侧而不是 SQL 里算：到期是**随时间变化**的判定，
  /// 写进查询会让同一行在不同时刻返回不同结果，缓存与分页都会跟着失真。
  bool get isDue {
    final dueAt = entry.dueAt;
    return dueAt != null && dueAt <= DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LiquidGlass(
        level: GlassLevel.elevated,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        showSpecular: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _CardHeading(entry: entry),
                  const SizedBox(height: 4),
                  _CardMeaning(meaning: entry.meaning),
                  const SizedBox(height: 6),
                  _CardMeta(entry: entry, isDue: isDue),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _CardAside(entry: entry),
          ],
        ),
      ),
    );
  }
}

/// 词形与两条状态徽标。
class _CardHeading extends StatelessWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            entry.term,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.lexiColors.label,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (entry.wrongWordActive)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: _CardTag(label: '错词', colorRole: _TagRole.danger),
          ),
        if (entry.isSuspended)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: _CardTag(label: '已暂停', colorRole: _TagRole.muted),
          ),
      ],
    );
  }
}

/// 释义摘要。
class _CardMeaning extends StatelessWidget {
  const new({required this.meaning});

  final String? meaning;

  @override
  Widget build(BuildContext context) {
    return Text(
      meaning ?? '暂无释义',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.lexiColors.secondaryLabel, fontSize: 13),
    );
  }
}

/// 初始化状态、掌握等级、语向与到期日。
class _CardMeta extends StatelessWidget {
  const new({required this.entry, required this.isDue});

  final WordListEntry entry;

  final bool isDue;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final dueAt = entry.dueAt;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        InitializationBadge(status: entry.initializationStatus),
        MasteryBadge(level: entry.masteryLevel),
        Text(
          '${entry.sourceLanguage} → ${entry.targetLanguage}',
          style: TextStyle(color: colors.tertiaryLabel, fontSize: 11),
        ),
        if (isDue) const _CardTag(label: '到期', colorRole: _TagRole.accent),
        if (dueAt != null)
          Text(
            formatDueDate(dueAt),
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 11),
          ),
      ],
    );
  }
}

/// 卡片右侧：朗读入口与掌握分。
class _CardAside extends StatelessWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SpeakerButton(),
        const SizedBox(height: 2),
        Text(
          '${entry.masteryScore}',
          style: TextStyle(
            color: colors.accent,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '熟练度',
          style: TextStyle(color: colors.tertiaryLabel, fontSize: 10),
        ),
      ],
    );
  }
}

/// 朗读发音按钮。
///
/// **当前是空实现**：音频服务层正在并行开发，接上之后只要把 [_speak]
/// 换成真正的播放器调用，按钮的位置与命中区都不用再动。
/// 在此之前保持「可点」，是为了先把入口立住——用户点下去不会有异常，
/// 也不会因为按钮被禁用而误以为这个词条不能朗读。
class _SpeakerButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '朗读发音',
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      onPressed: _speak,
      icon: Icon(
        Icons.volume_up_rounded,
        size: 16,
        color: context.lexiColors.tertiaryLabel,
      ),
    );
  }

  /// 音频层接线前的占位实现。
  void _speak() {}
}

/// 徽标色位。
enum _TagRole { danger, accent, muted }

/// 卡片上的小徽标（错词 / 已暂停 / 到期）。
class _CardTag extends StatelessWidget {
  const new({required this.label, required this.colorRole});

  final String label;

  final _TagRole colorRole;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final color = switch (colorRole) {
      _TagRole.danger => colors.danger,
      _TagRole.accent => colors.accent,
      _TagRole.muted => colors.tertiaryLabel,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
