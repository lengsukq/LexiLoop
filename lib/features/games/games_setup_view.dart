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
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/inline_notice.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 可开局的小游戏（精选保留核心拼词训练）。
const List<GameMode> miniGameModes = <GameMode>[GameMode.wordBuilder];

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
        PageHeader(
          title: '趣味训练',
          subtitle: '独立于每日复习队列。错词、近期忘记和模糊的词会优先出现。',
          leading: backButton(context, preferPop: false, fallbackLocation: '/'),
        ),
        const SizedBox(height: LexiSpace.s16),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(14) >= 24;
            final columns = largeText || constraints.maxWidth < 320
                ? 1
                : constraints.maxWidth >= 760
                ? 3
                : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * LexiSpace.s12) /
                columns;
            return Wrap(
              spacing: LexiSpace.s12,
              runSpacing: LexiSpace.s12,
              children: <Widget>[
                for (final mode in miniGameModes)
                  SizedBox(
                    width: width,
                    child: _ModeCard(
                      mode: mode,
                      selected: state.selectedMode == mode,
                      loading: state.loadingMode == mode,
                      onTap: loading ? null : () => onSelect(mode),
                    ),
                  ),
              ],
            );
          },
        ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          InlineNotice(message: state.error!),
        ],
        DisclosureSection(
          title: '玩法说明',
          child: Text(gameModeRule(state.selectedMode), style: LexiType.body),
        ),
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

  LexiTone get _tone => switch (mode) {
    GameMode.wordBuilder || GameMode.wordTetris => LexiTone.lavender,
    GameMode.listeningPick || GameMode.wordStack => LexiTone.sky,
    GameMode.meaningBlitz => LexiTone.peach,
    _ => LexiTone.mint,
  };

  IconData get _icon => switch (mode) {
    GameMode.wordBuilder => LucideIcons.puzzle,
    GameMode.listeningPick => LucideIcons.ear,
    GameMode.meaningBlitz => LucideIcons.languages,
    GameMode.whackAMole => LucideIcons.hammer,
    GameMode.wordStack => LucideIcons.layers,
    _ => LucideIcons.blocks,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tone = context.lexiTones.styleOf(_tone);
    return Surface(
      variant: SurfaceVariant.raised,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(LexiSpace.s16),
          decoration: BoxDecoration(
            color: selected ? tone.background : null,
            borderRadius: BorderRadius.circular(LexiRadius.lg),
            border: selected
                ? Border.all(color: colors.accentText, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(LexiSpace.s8),
                    decoration: BoxDecoration(
                      color: tone.background,
                      borderRadius: BorderRadius.circular(LexiRadius.sm),
                    ),
                    child: Icon(_icon, size: 24, color: tone.foreground),
                  ),
                  const Spacer(),
                  if (loading)
                    const SizedBox(
                      width: LexiSpace.s16,
                      height: LexiSpace.s16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (selected)
                    Icon(
                      LucideIcons.circleCheck,
                      size: 20,
                      color: colors.accentText,
                    ),
                ],
              ),
              const SizedBox(height: LexiSpace.s16),
              _ModeCardText(mode: mode),
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
      ],
    );
  }
}
