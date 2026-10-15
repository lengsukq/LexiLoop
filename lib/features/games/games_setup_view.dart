/// 小游戏准备页：选模式 → 开始。
///
/// 对应旧版 `games/games-setup.tsx`。旧版把「配对」与「音标」也做成入口卡片
/// 放在同一页；本版这两个功能有独立路由（`/match`、`/phonetics`），
/// 因此这里只列 4 个游戏，并在页脚给出跳转提示（由路由层接线）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 可开局的小游戏（配对与音标不在本页）。
const List<GameMode> miniGameModes = <GameMode>[
  GameMode.whackAMole,
  GameMode.wordBuilder,
  GameMode.wordStack,
  GameMode.wordTetris,
];

/// 每个模式的说明文案。
String gameModeSubtitle(GameMode mode) => switch (mode) {
  GameMode.wordBuilder => '按释义组合字母',
  GameMode.whackAMole => '锤出正确单词',
  GameMode.wordStack => '点词块搭高塔',
  GameMode.wordTetris => '点中下落单词',
  GameMode.match => '英文与释义配对',
  GameMode.phonetics => '听音辨音训练',
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
          style: TextStyle(
            color: colors.label,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '独立于每日复习队列。错词、近期忘记和模糊的词会优先出现。',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        for (final mode in miniGameModes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ModeCard(
              mode: mode,
              selected: state.selectedMode == mode,
              loading: state.loadingMode == mode,
              onTap: loading ? null : () => onSelect(mode),
            ),
          ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: 6),
          _ErrorBanner(message: state.error!),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: loading ? null : () => onStart(state.selectedMode),
          child: Text(loading ? '正在组题…' : '开始'),
        ),
        const SizedBox(height: 10),
        Text(
          '题量不足时无法开局：每个模式都需要至少 4 个带有效释义的可学习词条。',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.sports_esports_rounded,
                  size: 20,
                  color: selected ? colors.accent : colors.tertiaryLabel,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        gameModeTitle(mode),
                        style: TextStyle(
                          color: colors.label,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        gameModeSubtitle(mode),
                        style: TextStyle(
                          color: colors.quaternaryLabel,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
      ),
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
        color: colors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: colors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.dangerDeep, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
