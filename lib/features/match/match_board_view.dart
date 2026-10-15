/// 配对牌面的渲染层。
///
/// 左列英文、右列释义，两列的顺序由状态机的 `deck` 决定（开局时各自打乱）。
/// 卡片状态（已消除 / 选中 / 错配闪烁）全部来自 [MatchBoardState]，
/// 视图不自己记任何状态——旧版用 `useState` 维护 `matched`/`wrongFlash`，
/// 与 `matchedRef` 双份存储，正是「状态不一致」的温床。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/matching.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 配对牌面。
class MatchBoardView extends StatelessWidget {
  /// 以进行中状态与派发回调构造。
  const new({
    required this.playing,
    required this.onAction,
    required this.onExit,
    super.key,
  });

  /// 进行中状态。
  final MatchPlaying playing;

  /// 动作派发。
  final ValueChanged<MatchAction> onAction;

  /// 退出回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = playing.board;
    return Column(
      children: <Widget>[
        GameHud(
          title: gameModeTitle(GameMode.match),
          core: board.core,
          onExit: onExit,
          mistakeLabel: '错配',
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          '已配对 ${board.matchedCount}/${board.pairs.length} · 点击英文与对应释义',
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.secondaryLabel,
          ),
        ),
        const SizedBox(height: LexiSpace.s10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _Column(
                  side: MatchSide.word,
                  board: board,
                  onAction: onAction,
                ),
              ),
              const SizedBox(width: LexiSpace.s10),
              Expanded(
                child: _Column(
                  side: MatchSide.definition,
                  board: board,
                  onAction: onAction,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const new({required this.side, required this.board, required this.onAction});

  final MatchSide side;
  final MatchBoardState board;
  final ValueChanged<MatchAction> onAction;

  @override
  Widget build(BuildContext context) {
    final order = side == MatchSide.word
        ? board.deck.words
        : board.deck.definitions;
    return ListView.separated(
      itemCount: order.length,
      separatorBuilder: (_, _) => const SizedBox(height: LexiSpace.s8),
      itemBuilder: (context, index) {
        final pairIndex = order[index];
        if (pairIndex >= board.pairs.length) return const SizedBox.shrink();
        final pair = board.pairs[pairIndex];
        final ref = MatchCardRef(side: side, itemId: pair.itemId);
        return _Card(
          pair: pair,
          side: side,
          matched: board.matchedItemIds.contains(pair.itemId),
          selected: board.feedback.selected == ref,
          wrong: board.feedback.wrongFlash.contains(ref.key),
          locked: board.feedback.isLocked,
          onTap: () => onAction(TapMatchCard(side: side, itemId: pair.itemId)),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const new({
    required this.pair,
    required this.side,
    required this.matched,
    required this.selected,
    required this.wrong,
    required this.locked,
    required this.onTap,
  });

  final GameQuestion pair;
  final MatchSide side;
  final bool matched;
  final bool selected;
  final bool wrong;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final border = wrong
        ? colors.danger
        : (selected ? colors.accent : colors.borderSubtle);
    return Opacity(
      opacity: matched ? 0.28 : 1,
      child: Material(
        color: wrong
            ? Color.alphaBlend(
                colors.danger.withValues(alpha: 0.1),
                colors.card,
              )
            : (selected
                  ? Color.alphaBlend(
                      colors.accent.withValues(alpha: 0.1),
                      colors.card,
                    )
                  : colors.card),
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: matched || locked ? null : onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LexiRadius.md),
              border: Border.all(color: border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s10,
              vertical: LexiSpace.s8,
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              side == MatchSide.word ? pair.word.term : pair.word.definition,
              style: TextStyle(
                color: side == MatchSide.word
                    ? colors.label
                    : colors.secondaryLabel,
                fontSize:
                    (side == MatchSide.word ? LexiType.callout : LexiType.body)
                        .fontSize,
                fontWeight: side == MatchSide.word
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
