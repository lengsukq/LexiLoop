/// 首页练习入口的目录。
///
/// **为什么单独拆出来**：首页卡片只展示 4 个精选入口，「全部练习」弹层要
/// 展示完整分组。两处若各抄一份地址，新增模式时必然漏改一处；这里让卡片
/// 与弹层共用同一份 [practiceEntries]，路由继续由 [studyModeLocation] 生成，
/// 不在界面层手写 `'?mode='`。
///
/// **专项模式为什么排在自己的组里**：配对、音标、听力/拼写/句子、小游戏
/// 解决的是不同场景的练习。旧首页把「专项练习」与「更多趣味训练」做成两条
/// 孤立折叠行，既不在一张卡里，也读不出分组关系；现在分组是数据的一部分，
/// 界面只负责按 [practiceCategories] 渲染。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

/// 一组练习入口。
class PracticeCategory {
  /// 以组标题、图标与入口构造。
  const new({required this.title, required this.icon, required this.entries});

  /// 组标题。
  final String title;

  /// 组标题前的图标。
  final IconData icon;

  /// 组内入口。
  final List<PracticeEntry> entries;
}

/// 配对与音标。
const List<PracticeEntry> _pairingEntries = <PracticeEntry>[
  PracticeEntry(
    label: '限时配对',
    subtitle: '英文与释义组队',
    icon: LucideIcons.layoutGrid,
    location: '/match',
  ),
  PracticeEntry(
    label: '音标辨音',
    subtitle: '听音、音标与拼写',
    icon: LucideIcons.audioLines,
    location: '/phonetics',
  ),
];

/// 专项练习。
///
/// 不是 `const`：地址由 [studyModeLocation] 解析，编译期算不出来。
final List<PracticeEntry> _focusedEntries = <PracticeEntry>[
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

/// 趣味训练。
const List<PracticeEntry> _gameEntries = <PracticeEntry>[
  PracticeEntry(
    label: '单词拼图',
    subtitle: '点击字母完成拼写',
    icon: LucideIcons.puzzle,
    location: '/games?mode=WORD_BUILDER',
  ),
  PracticeEntry(
    label: '听音辨词',
    subtitle: '听发音选择词条',
    icon: LucideIcons.ear,
    location: '/games?mode=LISTENING_PICK',
  ),
  PracticeEntry(
    label: '词义冲刺',
    subtitle: '看英文选择释义',
    icon: LucideIcons.languages,
    location: '/games?mode=MEANING_BLITZ',
  ),
  PracticeEntry(
    label: '词汇地鼠',
    subtitle: '锤出正确单词',
    icon: LucideIcons.hammer,
    location: '/games?mode=WHACK_A_MOLE',
  ),
  PracticeEntry(
    label: '单词堆堆乐',
    subtitle: '点词块搭高塔',
    icon: LucideIcons.layers,
    location: '/games?mode=WORD_STACK',
  ),
  PracticeEntry(
    label: '词汇俄罗斯方块',
    subtitle: '点中下落的正确单词',
    icon: LucideIcons.blocks,
    location: '/games?mode=WORD_TETRIS',
  ),
];

/// 全部分组，顺序即「全部练习」弹层里的顺序。
final List<PracticeCategory> practiceCategories = <PracticeCategory>[
  const PracticeCategory(
    title: '配对与音标',
    icon: LucideIcons.layoutGrid,
    entries: _pairingEntries,
  ),
  PracticeCategory(
    title: '专项练习',
    icon: LucideIcons.target,
    entries: _focusedEntries,
  ),
  const PracticeCategory(
    title: '趣味训练',
    icon: LucideIcons.gamepad2,
    entries: _gameEntries,
  ),
];

/// 全部 11 项练习，供计数与测试使用。
final List<PracticeEntry> practiceEntries = <PracticeEntry>[
  for (final category in practiceCategories) ...category.entries,
];

/// 首页首屏展示的 4 个精选入口。
///
/// **显式列出而不是取前四项**：目录顺序调整时，首页展示的入口应该由设计
/// 决定，而不是被数据顺序悄悄改掉。四格覆盖配对、音标、专项与小游戏各一项；
/// 缺项时抛错，避免首页静默少一格。
final List<PracticeEntry> featuredPracticeEntries = <PracticeEntry>[
  _featuredEntry('/match'),
  _featuredEntry('/phonetics'),
  _featuredEntry(studyModeLocation(StudyMode.listening)),
  _featuredEntry('/games?mode=WORD_BUILDER'),
];

/// 按地址从目录里取精选入口。
PracticeEntry _featuredEntry(String location) {
  for (final entry in practiceEntries) {
    if (entry.location == location) return entry;
  }
  throw StateError('练习目录缺少 $location');
}
