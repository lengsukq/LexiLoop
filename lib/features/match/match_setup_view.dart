/// 配对准备页：选预设 → 开始。
///
/// 对应旧版 `match/page.tsx` 的准备卡片（3 个预设 + 参数回显）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/inline_notice.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/selection_card.dart';

/// 配对准备页。
class MatchSetupView extends StatelessWidget {
  /// 以状态与回调构造。
  const new({
    required this.state,
    required this.onSelect,
    required this.onStart,
    super.key,
  });

  /// 准备阶段状态。
  final MatchSetup state;

  /// 选择预设。
  final ValueChanged<MatchPreset> onSelect;

  /// 开始。
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        // **准备阶段必须能离开这一页**：`/match` 是顶层路由，没有侧边栏，
        // 而 `exit()` 只是把状态退回 `MatchSetup`——也就是用户已经站着的
        // 地方。此前准备页唯一的出口是浏览器/系统的返回手势，
        // 桌面端等于没有。这里用统一的返回动作：能出栈就出栈，否则回训练页。
        PageHeader(
          title: '限时词汇配对',
          subtitle: '将英文与中文释义配对。',
          leading: backButton(
            context,
            preferPop: false,
            fallbackLocation: gamesPath,
          ),
        ),
        const SizedBox(height: LexiSpace.s16),
        for (final preset in matchPresets)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s8),
            child: _PresetCard(
              preset: preset,
              selected: state.preset.id == preset.id,
              onTap: state.loading ? null : () => onSelect(preset),
            ),
          ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          InlineNotice(message: state.error!),
        ],
        const DisclosureSection(
          title: '配对规则',
          child: Text(
            '连续配对获得连击分。错词、近期遗忘和模糊的词会优先出现；本轮练习不占用今日计划。',
            style: LexiType.body,
          ),
        ),
        const SizedBox(height: LexiSpace.s14),
        FilledButton(
          onPressed: state.loading ? null : onStart,
          child: Text(state.loading ? '正在组题…' : '开始配对'),
        ),
        const SizedBox(height: LexiSpace.s10),
        Text(
          '至少需要 4 个带释义且释义不重复的可学习词条。',
          textAlign: TextAlign.center,
          style: LexiType.caption.copyWith(
            color: context.lexiColors.tertiaryLabel,
          ),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const new({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final MatchPreset preset;
  final bool selected;
  final VoidCallback? onTap;

  LexiTone get _tone => switch (preset.id) {
    'relaxed' => LexiTone.mint,
    'sprint' => LexiTone.peach,
    _ => LexiTone.sky,
  };

  @override
  Widget build(BuildContext context) {
    return SelectionCard(
      title: preset.name,
      subtitle:
          '${preset.pairs} 组 · ${preset.seconds} 秒 · ${preset.description}',
      tone: _tone,
      selected: selected,
      onTap: onTap,
      compact: true,
    );
  }
}
