/// 结算面板（小游戏 / 配对 / 音标共用）。
///
/// 对应旧版 `components/game-result.tsx`（Hero / Stats / Accuracy）、
/// `components/leaderboard-panel.tsx`（高分榜）与各 `*-result.tsx` 的拼装。
/// 三个业务线的结算页只差文案与按钮，因此做成一个组件 + 一份文案对象。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 结算页的文案。
class GameResultLabels {
  /// 以各字段构造。
  const new({
    required this.title,
    required this.primary,
    required this.missed,
    required this.exit,
  });

  /// 得分标题（如「词汇地鼠得分」）。
  final String title;

  /// 「一次正确」这一格的中文标签。
  final String primary;

  /// 「未完成」这一格的中文标签。
  final String missed;

  /// 退出按钮文案。
  final String exit;
}

/// 结算面板。
class GameResultPanel extends StatelessWidget {
  /// 以各字段构造。
  const new({
    required this.labels,
    required this.result,
    required this.onReplay,
    required this.onExit,
    this.mistakes = const <String>[],
    super.key,
  });

  /// 文案。
  final GameResultLabels labels;

  /// 结算结果。
  final GameResult result;

  /// 「再来一局」回调。
  final VoidCallback onReplay;

  /// 退出回调。
  final VoidCallback onExit;

  /// 本轮失误的词条（`词条 · 释义`），为空时不展示。
  final List<String> mistakes;

  @override
  Widget build(BuildContext context) {
    final summary = result.summary;
    return ListView(
      children: <Widget>[
        _Hero(labels: labels, result: result),
        const SizedBox(height: 14),
        _Stats(labels: labels, summary: summary),
        const SizedBox(height: 14),
        _Accuracy(accuracy: summary.accuracy),
        if (mistakes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _MistakeList(mistakes: mistakes),
        ],
        const SizedBox(height: 14),
        _Leaderboard(leaderboard: result.leaderboard),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onReplay,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('再来一局'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onExit,
                child: Text(labels.exit),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const new({required this.labels, required this.result});

  final GameResultLabels labels;
  final GameResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.xl),
      showSpecular: true,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      child: Column(
        children: <Widget>[
          Text(
            labels.title,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          Text(
            '${result.score}',
            style: TextStyle(
              color: colors.label,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '评级 ${result.rank.label} · 用时 '
            '${(result.summary.elapsedMs / 1000).toStringAsFixed(1)} 秒 · '
            '最长 ${result.summary.maxCombo} 连击',
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Text(
            '历史最高分 ${result.leaderboard.best}',
            style: TextStyle(color: colors.accent, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const new({required this.labels, required this.summary});

  final GameResultLabels labels;
  final GameRoundSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        _StatCell(
          label: labels.primary,
          value: summary.firstTryCorrect,
          color: colors.success,
        ),
        const SizedBox(width: 8),
        _StatCell(
          label: '纠正完成',
          value: summary.recovered,
          color: colors.warning,
        ),
        const SizedBox(width: 8),
        _StatCell(
          label: labels.missed,
          value: summary.missed,
          color: colors.danger,
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const new({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(LexiRadius.md),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: <Widget>[
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: TextStyle(color: colors.quaternaryLabel, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Accuracy extends StatelessWidget {
  const new({required this.accuracy});

  final int accuracy;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '一次正确率',
                style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
              ),
            ),
            Text(
              '$accuracy%',
              style: TextStyle(
                color: colors.label,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: accuracy / 100,
            minHeight: 6,
            backgroundColor: colors.fill,
          ),
        ),
      ],
    );
  }
}

class _MistakeList extends StatelessWidget {
  const new({required this.mistakes});

  final List<String> mistakes;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.subtle,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本轮失误 ${mistakes.length} 个 · 已记入错词，后续会优先出现',
            style: TextStyle(
              color: colors.warningDeep,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final item in mistakes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  const new({required this.leaderboard});

  final GameLeaderboard leaderboard;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    if (leaderboard.top.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          leaderboard.isNewBest
              ? '新纪录！本轮第 1 名'
              : '本轮第 ${leaderboard.rank} 名 · 历史最佳 ${leaderboard.best}',
          style: TextStyle(
            color: leaderboard.isNewBest ? colors.warningDeep : colors.accent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < leaderboard.top.length; index += 1)
          _ScoreRow(index: index, entry: leaderboard.top[index]),
      ],
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const new({required this.index, required this.entry});

  final int index;
  final GameHighScore entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final playedAt = DateTime.fromMillisecondsSinceEpoch(entry.playedAt);
    final stamp =
        '${playedAt.month}-${playedAt.day} '
        '${playedAt.hour.toString().padLeft(2, '0')}:'
        '${playedAt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 26,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: colors.tertiaryLabel,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${entry.score}',
              style: TextStyle(
                color: colors.label,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '连击 ${entry.detail.maxCombo} · $stamp',
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
