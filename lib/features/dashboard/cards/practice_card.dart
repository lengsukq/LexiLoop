/// 首页「趣味训练」入口卡片。
///
/// 对应旧版 `app/(main)/page.tsx` 的「趣味训练」区块。
///
/// **为什么这些入口在首页而不是导航栏**：小游戏与音标训练是「独立模式，
/// 不占用今日复习队列」（旧版原文），放进主导航会让人误以为它们是日常
/// 必做项。放在首页作为可选项，语义更准确。
///
/// 专项学习模式（听力、拼写、句子）也归在这里：它们同样不计入每日计划的
/// 配额（旧版 `dailyProgress` 只统计 `DAILY` 会话），但走的是学习会话页，
/// 因此地址是 `/study?mode=…` 而不是小游戏页。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 趣味训练入口。
class PracticeCard extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '练习',
                style: LexiType.title.copyWith(color: context.lexiColors.label),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/games'),
              child: const Text('趣味训练'),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 880 ? 4 : 2;
            final width =
                (constraints.maxWidth - (columns - 1) * LexiSpace.s12) /
                columns;
            return Wrap(
              spacing: LexiSpace.s12,
              runSpacing: LexiSpace.s12,
              children: <Widget>[
                for (final entry in practiceEntries.take(4))
                  SizedBox(
                    width: width,
                    child: _PracticeTile(entry: entry),
                  ),
              ],
            );
          },
        ),
        _PracticeGroup(
          title: '专项练习',
          entries: practiceEntries
              .where(
                (entry) =>
                    !entry.location.startsWith('/games') &&
                    entry.location != '/match' &&
                    entry.location != '/phonetics',
              )
              .toList(),
        ),
        _PracticeGroup(
          title: '更多趣味训练',
          entries: practiceEntries
              .where((entry) => entry.location.startsWith('/games'))
              .toList(),
        ),
      ],
    );
  }
}

class _PracticeTile extends StatelessWidget {
  const new({required this.entry});
  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) => Surface(
    variant: SurfaceVariant.raised,
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: () => context.go(entry.location),
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(LexiSpace.s8),
              decoration: BoxDecoration(
                color: LexiTone.lavender.background(
                  Theme.of(context).brightness,
                ),
                borderRadius: BorderRadius.circular(LexiRadius.sm),
              ),
              child: Icon(
                entry.icon,
                size: 22,
                color: LexiTone.lavender.foreground(
                  Theme.of(context).brightness,
                ),
              ),
            ),
            const SizedBox(height: LexiSpace.s10),
            Text(
              entry.label,
              style: LexiType.callout.copyWith(color: context.lexiColors.label),
            ),
            const SizedBox(height: LexiSpace.s4),
            Text(
              entry.subtitle,
              style: LexiType.caption.copyWith(
                color: context.lexiColors.secondaryLabel,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 一个训练入口。
class PracticeEntry {
  /// 以各字段构造。
  const new({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.location,
  });

  /// 名称。
  final String label;

  /// 一句话说明。
  final String subtitle;

  /// 图标。
  final IconData icon;

  /// 目标地址（可带 query）。
  final String location;
}

/// 全部训练入口。
///
/// 顺序与旧版首页一致：配对 → 音标 → 四个小游戏 → 三个专项模式。
/// 专项模式排在最后：它们借用同一个学习会话页，与小游戏的「玩一把」
/// 心智不同，混排会让用户以为点开还是游戏。
///
/// **不是 `const` 列表**：专项入口的地址由 [studyModeLocation] 解析，
/// 它要读导航表才能得到 `/study`，编译期算不出来。
final List<PracticeEntry> practiceEntries = <PracticeEntry>[
  const PracticeEntry(
    label: '限时配对',
    subtitle: '英文与释义组队',
    icon: LucideIcons.layoutGrid,
    location: '/match',
  ),
  const PracticeEntry(
    label: '音标辨音',
    subtitle: '听音、音标与拼写',
    icon: LucideIcons.audioLines,
    location: '/phonetics',
  ),
  const PracticeEntry(
    label: '单词拼图',
    subtitle: '点击字母完成拼写',
    icon: LucideIcons.puzzle,
    location: '/games?mode=WORD_BUILDER',
  ),
  const PracticeEntry(
    label: '听音辨词',
    subtitle: '听发音选择词条',
    icon: LucideIcons.ear,
    location: '/games?mode=LISTENING_PICK',
  ),
  const PracticeEntry(
    label: '词义冲刺',
    subtitle: '看英文选择释义',
    icon: LucideIcons.languages,
    location: '/games?mode=MEANING_BLITZ',
  ),
  const PracticeEntry(
    label: '词汇地鼠',
    subtitle: '锤出正确单词',
    icon: LucideIcons.hammer,
    location: '/games?mode=WHACK_A_MOLE',
  ),
  const PracticeEntry(
    label: '单词堆堆乐',
    subtitle: '点词块搭高塔',
    icon: LucideIcons.layers,
    location: '/games?mode=WORD_STACK',
  ),
  const PracticeEntry(
    label: '词汇俄罗斯方块',
    subtitle: '点中下落的正确单词',
    icon: LucideIcons.blocks,
    location: '/games?mode=WORD_TETRIS',
  ),
  PracticeEntry(
    label: '听力拼写',
    subtitle: '听发音后输入词条',
    icon: LucideIcons.headphones,
    location: studyModeLocation(StudyMode.listening),
  ),
  PracticeEntry(
    label: '中文拼写',
    subtitle: '根据释义回忆英文',
    icon: LucideIcons.pencil,
    location: studyModeLocation(StudyMode.spelling),
  ),
  PracticeEntry(
    label: '句子复习',
    subtitle: '理解与还原完整句子',
    icon: LucideIcons.messagesSquare,
    location: studyModeLocation(StudyMode.sentenceReview),
  ),
];

/// 一组可展开的训练入口。
class _PracticeGroup extends StatelessWidget {
  const new({required this.title, required this.entries});

  final String title;
  final List<PracticeEntry> entries;

  @override
  Widget build(BuildContext context) => DisclosureSection(
    title: title,
    child: Column(
      children: <Widget>[
        for (final entry in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(entry.icon),
            title: Text(entry.label, style: LexiType.callout),
            subtitle: Text(entry.subtitle, style: LexiType.footnote),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.go(entry.location),
          ),
      ],
    ),
  );
}
