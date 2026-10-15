/// 首页「趣味训练」入口卡片。
///
/// 对应旧版 `app/(main)/page.tsx` 的「趣味训练」区块。
///
/// **为什么这些入口在首页而不是导航栏**：小游戏与音标训练是「独立模式，
/// 不占用今日复习队列」（旧版原文），放进主导航会让人误以为它们是日常
/// 必做项。放在首页作为可选项，语义更准确。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
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
/// 顺序与旧版首页一致：配对 → 音标 → 四个小游戏。
const List<PracticeEntry> practiceEntries = <PracticeEntry>[
  PracticeEntry(
    label: '限时配对',
    subtitle: '英文与释义组队',
    icon: Icons.grid_view_rounded,
    location: '/match',
  ),
  PracticeEntry(
    label: '音标辨音',
    subtitle: '听音、音标与拼写',
    icon: Icons.graphic_eq_rounded,
    location: '/phonetics',
  ),
  PracticeEntry(
    label: '单词拼图',
    subtitle: '点击字母完成拼写',
    icon: Icons.extension_outlined,
    location: '/games?mode=WORD_BUILDER',
  ),
  PracticeEntry(
    label: '词汇地鼠',
    subtitle: '锤出正确单词',
    icon: Icons.hardware_outlined,
    location: '/games?mode=WHACK_A_MOLE',
  ),
  PracticeEntry(
    label: '单词堆堆乐',
    subtitle: '点词块搭高塔',
    icon: Icons.layers_outlined,
    location: '/games?mode=WORD_STACK',
  ),
  PracticeEntry(
    label: '词汇俄罗斯方块',
    subtitle: '点中下落的正确单词',
    icon: Icons.view_module_outlined,
    location: '/games?mode=WORD_TETRIS',
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
