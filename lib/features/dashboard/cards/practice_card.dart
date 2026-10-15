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
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 趣味训练入口。
class PracticeCard extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return DashboardCard(
      title: '趣味训练',
      icon: Icons.sports_esports_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '独立模式，不占用今日复习队列',
            style: TextStyle(color: colors.quaternaryLabel, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: entryGap,
            runSpacing: entryGap,
            children: <Widget>[
              for (final entry in practiceEntries)
                _PracticeEntryTile(entry: entry),
            ],
          ),
        ],
      ),
    );
  }
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
    icon: Icons.grid_view_rounded,
    location: '/match',
  ),
  const PracticeEntry(
    label: '音标辨音',
    subtitle: '听音、音标与拼写',
    icon: Icons.graphic_eq_rounded,
    location: '/phonetics',
  ),
  const PracticeEntry(
    label: '单词拼图',
    subtitle: '点击字母完成拼写',
    icon: Icons.extension_outlined,
    location: '/games?mode=WORD_BUILDER',
  ),
  const PracticeEntry(
    label: '词汇地鼠',
    subtitle: '锤出正确单词',
    icon: Icons.hardware_outlined,
    location: '/games?mode=WHACK_A_MOLE',
  ),
  const PracticeEntry(
    label: '单词堆堆乐',
    subtitle: '点词块搭高塔',
    icon: Icons.layers_outlined,
    location: '/games?mode=WORD_STACK',
  ),
  const PracticeEntry(
    label: '词汇俄罗斯方块',
    subtitle: '点中下落的正确单词',
    icon: Icons.view_module_outlined,
    location: '/games?mode=WORD_TETRIS',
  ),
  PracticeEntry(
    label: '听力拼写',
    subtitle: '听发音后输入词条',
    icon: Icons.headphones_rounded,
    location: studyModeLocation(StudyMode.listening),
  ),
  PracticeEntry(
    label: '中文拼写',
    subtitle: '根据释义回忆英文',
    icon: Icons.draw_rounded,
    location: studyModeLocation(StudyMode.spelling),
  ),
  PracticeEntry(
    label: '句子复习',
    subtitle: '理解与还原完整句子',
    icon: Icons.forum_outlined,
    location: studyModeLocation(StudyMode.sentenceReview),
  ),
];

/// 单个入口磁贴。
class _PracticeEntryTile extends StatelessWidget {
  const new({required this.entry});

  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SizedBox(
      width: tileWidth,
      child: Material(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: () => context.go(entry.location),
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: tilePaddingH,
              vertical: tilePaddingV,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(entry.icon, size: 18, color: colors.accent),
                const SizedBox(height: 8),
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 磁贴宽度：两列。
const double tileWidth = 150;

/// 磁贴之间的间距。
const double entryGap = 8;

/// 磁贴水平内边距。
const double tilePaddingH = 12;

/// 磁贴垂直内边距。
const double tilePaddingV = 10;
