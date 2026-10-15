/// 结算面板（小游戏 / 配对 / 音标共用）。
///
/// 对应旧版 `components/game-result.tsx`（Hero / Stats / Accuracy）、
/// `components/leaderboard-panel.tsx`（高分榜）与各 `*-result.tsx` 的拼装。
/// 三个业务线的结算页只差文案与按钮，因此做成一个组件 + 一份文案对象。
///
/// 错词列表对应旧版 `components/game-summary.tsx` 的 `SummaryRow`：
/// 行内先给出词条与释义，点开还有「看词条详情」的入口。旧版点开的是
/// 助记弹窗（`word-mnemonic-sheet.tsx`，含 AI 生成内容），那部分不在本次范围。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/domain/games/game_mistake.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

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
    this.mistakes = const <GameMistake>[],
    this.onOpenWord,
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

  /// 本轮失误的词条，为空时不展示。
  final List<GameMistake> mistakes;

  /// 打开词条详情（跳到 `/words/:id`）；为空时不给入口。
  final ValueChanged<int>? onOpenWord;

  @override
  Widget build(BuildContext context) {
    final summary = result.summary;
    return ListView(
      children: <Widget>[
        _Hero(labels: labels, result: result),
        const SizedBox(height: LexiSpace.s14),
        _Stats(labels: labels, summary: summary),
        const SizedBox(height: LexiSpace.s14),
        _Accuracy(accuracy: summary.accuracy),
        if (mistakes.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s14),
          _MistakeList(mistakes: mistakes, onOpenWord: onOpenWord),
        ],
        const SizedBox(height: LexiSpace.s14),
        _Leaderboard(leaderboard: result.leaderboard),
        const SizedBox(height: LexiSpace.s16),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onReplay,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('再来一局'),
              ),
            ),
            const SizedBox(width: LexiSpace.s10),
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
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.xl),
      padding: const EdgeInsets.symmetric(
        vertical: LexiSpace.s24,
        horizontal: LexiSpace.s20,
      ),
      child: Column(
        children: <Widget>[
          Text(
            labels.title,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '${result.score}',
            style: LexiType.hero.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: LexiSpace.s2),
          Text(
            '评级 ${result.rank.label} · 用时 '
            '${(result.summary.elapsedMs / 1000).toStringAsFixed(1)} 秒 · '
            '最长 ${result.summary.maxCombo} 连击',
            style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
          ),
          const SizedBox(height: LexiSpace.s6),
          Text(
            '历史最高分 ${result.leaderboard.best}',
            style: LexiType.footnote.copyWith(color: colors.accent),
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
        const SizedBox(width: LexiSpace.s8),
        _StatCell(
          label: '纠正完成',
          value: summary.recovered,
          color: colors.warning,
        ),
        const SizedBox(width: LexiSpace.s8),
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
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s10),
        child: Column(
          children: <Widget>[
            Text(
              '$value',
              style: LexiType.title2.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              style: LexiType.caption.copyWith(color: colors.quaternaryLabel),
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
                style: LexiType.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Text(
              '$accuracy%',
              style: LexiType.callout.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s6),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.pill),
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

/// 错词列表：每行先给出词条与释义，点开还有「看词条详情」。
///
/// 用 StatefulWidget 记住展开的那一行（同时只展开一行）：错词可能有十几个，
/// 全部展开会把排行榜挤出屏幕；一次只看一个词条的完整释义更接近旧版
/// 助记弹窗「一次一个词」的节奏。
class _MistakeList extends StatefulWidget {
  const new({required this.mistakes, required this.onOpenWord});

  final List<GameMistake> mistakes;
  final ValueChanged<int>? onOpenWord;

  @override
  State<_MistakeList> createState() => _MistakeListState();
}

class _MistakeListState extends State<_MistakeList> {
  /// 当前展开的词条 ID；为空表示全部折叠。
  int? _expandedWordId;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.all(LexiSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '本轮失误 ${widget.mistakes.length} 个 · 已记入错词，后续会优先出现',
            style: LexiType.footnote.copyWith(
              color: colors.warningDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s4),
          for (final mistake in widget.mistakes)
            _MistakeRow(
              mistake: mistake,
              expanded: _expandedWordId == mistake.wordId,
              onToggle: () => setState(() {
                _expandedWordId = _expandedWordId == mistake.wordId
                    ? null
                    : mistake.wordId;
              }),
              onOpenWord: widget.onOpenWord,
            ),
        ],
      ),
    );
  }
}

/// 一行错词。
class _MistakeRow extends StatelessWidget {
  const new({
    required this.mistake,
    required this.expanded,
    required this.onToggle,
    required this.onOpenWord,
  });

  final GameMistake mistake;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int>? onOpenWord;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: LexiSpace.s6,
            horizontal: LexiSpace.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      mistake.term,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LexiType.body.copyWith(
                        color: colors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: colors.tertiaryLabel,
                  ),
                ],
              ),
              Text(
                mistake.definition,
                maxLines: expanded ? null : 2,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
              ),
              if (expanded && onOpenWord != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => onOpenWord!(mistake.wordId),
                    child: const Text('看词条详情'),
                  ),
                ),
            ],
          ),
        ),
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
          style: LexiType.body.copyWith(
            color: leaderboard.isNewBest ? colors.warningDeep : colors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
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
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _indexColumnWidth,
            child: Text(
              '${index + 1}',
              style: LexiType.footnote.copyWith(
                color: colors.tertiaryLabel,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${entry.score}',
              style: LexiType.callout.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '连击 ${entry.detail.maxCombo} · $stamp',
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 序号列宽——两位数以内右对齐。
const double _indexColumnWidth = 26;
