/// 小游戏准备页：选模式 → 开始。
///
/// 对应旧版 `games/games-setup.tsx`。旧版把「配对」与「音标」也做成入口卡片
/// 放在同一页；本版这两个功能有独立路由（`/match`、`/phonetics`），
/// 因此这里只列 6 个游戏，并在页脚给出跳转提示（由路由层接线）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 可开局的小游戏（配对与音标不在本页）。
///
/// 顺序与旧版 `GAME_MODES` 一致，方便与旧界面逐格对照。
const List<GameMode> miniGameModes = <GameMode>[
  GameMode.wordBuilder,
  GameMode.listeningPick,
  GameMode.meaningBlitz,
  GameMode.whackAMole,
  GameMode.wordStack,
  GameMode.wordTetris,
];

/// 每个模式的副标题（旧版 `GAME_CONFIG[mode].subtitle`）。
String gameModeSubtitle(GameMode mode) => switch (mode) {
  GameMode.wordBuilder => '根据释义组合字母',
  GameMode.listeningPick => '听发音快速选词',
  GameMode.meaningBlitz => '限时选择正确释义',
  GameMode.whackAMole => '锤出正确单词',
  GameMode.wordStack => '点词块搭高塔',
  GameMode.wordTetris => '点中下落单词',
  GameMode.match => '英文与释义配对',
  GameMode.phonetics => '听音辨音训练',
};

/// 每个模式的规则（旧版 `GAME_CONFIG[mode].rule`）。
///
/// 旧版把这条文案印在游戏页头的渐变卡片里；本版页头只有模式标题与进度，
/// 因此把它放到准备页的模式卡片上，玩家选之前就能看清怎么玩。
/// 配对与音标不在旧版 `GAME_CONFIG` 里，取旧版入口卡片的说明文案。
String gameModeRule(GameMode mode) => switch (mode) {
  GameMode.wordBuilder => '点击打乱的字母拼出英文词条',
  GameMode.listeningPick => '听到发音后，从四个词中选出正确答案',
  GameMode.meaningBlitz => '看到英文后，快速选择对应的中文释义',
  GameMode.whackAMole => '看释义，在地鼠缩回前锤中正确单词',
  GameMode.wordStack => '看释义，点选滚动词块堆高塔',
  GameMode.wordTetris => '看释义，点中下落的正确单词',
  GameMode.match => '英文与释义组队配对，连击计分',
  GameMode.phonetics => '听音、音标与单词三向匹配',
};

/// 游戏准备页。
class GamesSetupView extends StatelessWidget {
  /// 以状态与回调构造。
  const new({
    required this.state,
    required this.onSelect,
    required this.onStart,
    super.key,
  });

  /// 准备阶段状态。
  final GamesSetup state;

  /// 选择模式。
  final ValueChanged<GameMode> onSelect;

  /// 开始。
  final ValueChanged<GameMode> onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final loading = state.loadingMode != null;
    return ListView(
      children: <Widget>[
        Text(
          '趣味训练',
          style: LexiType.page.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        Text(
          '独立于每日复习队列。错词、近期忘记和模糊的词会优先出现。',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s16),
        for (final mode in miniGameModes)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s8),
            child: _ModeCard(
              mode: mode,
              selected: state.selectedMode == mode,
              loading: state.loadingMode == mode,
              onTap: loading ? null : () => onSelect(mode),
            ),
          ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          _ErrorBanner(message: state.error!),
        ],
        const SizedBox(height: LexiSpace.s14),
        FilledButton(
          onPressed: loading ? null : () => onStart(state.selectedMode),
          child: Text(loading ? '正在组题…' : '开始'),
        ),
        const SizedBox(height: LexiSpace.s10),
        Text(
          '题量不足时无法开局：每个模式都需要至少 4 个带有效释义的可学习词条。',
          textAlign: TextAlign.center,
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const new({
    required this.mode,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final GameMode mode;
  final bool selected;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: selected
          ? Color.alphaBlend(
              colors.accent.withValues(alpha: LexiTint.tint),
              colors.card,
            )
          : colors.card,
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
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.sports_esports_rounded,
                size: 20,
                color: selected ? colors.accent : colors.tertiaryLabel,
              ),
              const SizedBox(width: LexiSpace.s10),
              Expanded(child: _ModeCardText(mode: mode)),
              if (loading)
                const SizedBox(
                  width: LexiSpace.s16,
                  height: LexiSpace.s16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCardText extends StatelessWidget {
  const new({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          gameModeTitle(mode),
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          gameModeSubtitle(mode),
          style: LexiType.footnote.copyWith(color: colors.quaternaryLabel),
        ),
        const SizedBox(height: LexiSpace.s2),
        Text(
          gameModeRule(mode),
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const new({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      padding: const EdgeInsets.all(LexiSpace.s12),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              message,
              style: LexiType.footnote.copyWith(color: colors.dangerDeep),
            ),
          ),
        ],
      ),
    );
  }
}
