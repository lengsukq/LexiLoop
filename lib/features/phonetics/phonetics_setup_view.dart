/// 音标训练的准备页与结算页。
///
/// 准备页只提供口音选择与开始按钮：48 音标目录是**静态教学资产**，
/// 本版没有做目录浏览页（旧版 `phonetic-learn.tsx` 的完整知识库浏览），
/// 目录内容改在每题的「解析」里按需展示——用户练到哪个音就看到哪个音的
/// 要领，比先读一遍 48 条更符合训练场景。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

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
        // 与配对页同一条理由：顶层路由的准备页必须能离开这一页。
        PageHeader(
          title: '音标辨音训练',
          subtitle:
              '听音、音标与单词三向匹配。每轮 $phoneticItemCount 题 / '
              '$phoneticDurationSeconds 秒，解析里给出 48 音标目录的发音要领。',
          leading: backButton(
            context,
            preferPop: false,
            fallbackLocation: gamesPath,
          ),
        ),
        const SizedBox(height: LexiSpace.s16),
        Text(
          '口音',
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Row(
          children: <Widget>[
            for (final accent in Accent.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: LexiSpace.s8),
                  child: _AccentCard(
                    accent: accent,
                    selected: state.accent == accent,
                    onTap: state.loading ? null : () => onSelectAccent(accent),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: LexiSpace.s14),
        _CatalogSummary(),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s12),
          Container(
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: LexiTint.tint),
              borderRadius: BorderRadius.circular(LexiRadius.md),
            ),
            padding: const EdgeInsets.all(LexiSpace.s12),
            child: Text(
              state.error!,
              style: LexiType.footnote.copyWith(color: colors.dangerDeep),
            ),
          ),
        ],
        const SizedBox(height: LexiSpace.s16),
        FilledButton(
          onPressed: state.loading ? null : onStart,
          child: Text(state.loading ? '正在组题…' : '开始'),
        ),
        const SizedBox(height: LexiSpace.s10),
        Text(
          '至少需要 $phoneticMinimumItemCount 个带对应口音音标的可学习单词。',
          textAlign: TextAlign.center,
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
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
      color: selected
          ? colors.accent.withValues(alpha: LexiTint.tint)
          : colors.fill,
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
          padding: const EdgeInsets.symmetric(vertical: LexiSpace.s14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: LexiType.callout.copyWith(
              color: selected ? colors.accent : colors.label,
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
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '目录：$phonemeCatalogSize 个音标 · '
            '${contrastGroups.length} 组易混对比 · '
            '${accentDiffs.length} 条美英差异',
            style: LexiType.body.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s6),
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
                    horizontal: LexiSpace.s8,
                    vertical: LexiSpace.s4,
                  ),
                  child: Text(
                    entry.display,
                    style: LexiType.footnote.copyWith(
                      color: colors.secondaryLabel,
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
