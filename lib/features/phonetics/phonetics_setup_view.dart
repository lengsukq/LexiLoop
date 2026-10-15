/// 音标训练的准备页与结算页。
///
/// 准备页只提供口音选择与开始按钮：48 音标目录是**静态教学资产**，
/// 本版没有做目录浏览页（旧版 `phonetic-learn.tsx` 的完整知识库浏览），
/// 目录内容改在每题的「解析」里按需展示——用户练到哪个音就看到哪个音的
/// 要领，比先读一遍 48 条更符合训练场景。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 音标训练准备页。
class PhoneticsSetupView extends StatelessWidget {
  /// 以状态与回调构造。
  const new({
    required this.state,
    required this.onSelectAccent,
    required this.onStart,
    super.key,
  });

  /// 准备阶段状态。
  final PhoneticSetup state;

  /// 选择口音。
  final ValueChanged<Accent> onSelectAccent;

  /// 开始。
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListView(
      children: <Widget>[
        Text(
          '音标辨音训练',
          style: TextStyle(
            color: colors.label,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '听音、音标与单词三向匹配。每轮 $phoneticItemCount 题 / '
          '$phoneticDurationSeconds 秒，解析里给出 48 音标目录的发音要领。',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
        ),
        const SizedBox(height: 16),
        Text(
          '口音',
          style: TextStyle(
            color: colors.label,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final accent in Accent.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _AccentCard(
                    accent: accent,
                    selected: state.accent == accent,
                    onTap: state.loading ? null : () => onSelectAccent(accent),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _CatalogSummary(),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(LexiRadius.md),
            ),
            padding: const EdgeInsets.all(12),
            child: Text(
              state.error!,
              style: TextStyle(color: colors.dangerDeep, fontSize: 12.5),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: state.loading ? null : onStart,
          child: Text(state.loading ? '正在组题…' : '开始'),
        ),
        const SizedBox(height: 10),
        Text(
          '至少需要 $phoneticMinimumItemCount 个带对应口音音标的可学习单词。',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _AccentCard extends StatelessWidget {
  const new({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final Accent accent;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final label = accent == Accent.us ? '美式音标' : '英式音标';
    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.12) : colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LexiRadius.md),
            border: Border.all(
              color: selected ? colors.accent : colors.borderSubtle,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.accent : colors.label,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogSummary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.subtle,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '目录：$phonemeCatalogSize 个音标 · '
            '${contrastGroups.length} 组易混对比 · '
            '${accentDiffs.length} 条美英差异',
            style: TextStyle(
              color: colors.label,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final entry in phonemeCatalog.take(12))
                Container(
                  decoration: BoxDecoration(
                    color: colors.fill,
                    borderRadius: BorderRadius.circular(LexiRadius.sm),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    entry.display,
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 音标训练结算页。
class PhoneticsResultView extends StatelessWidget {
  /// 以结算结果与回调构造。
  const new({
    required this.result,
    required this.onReplay,
    required this.onExit,
    super.key,
  });

  /// 结算结果。
  final GameResult result;

  /// 再来一局。
  final VoidCallback onReplay;

  /// 返回准备页。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return GameResultPanel(
      labels: const GameResultLabels(
        title: '音标训练得分',
        primary: '一次听对',
        missed: '超时或跳过',
        exit: '更换口音',
      ),
      result: result,
      onReplay: onReplay,
      onExit: onExit,
    );
  }
}
