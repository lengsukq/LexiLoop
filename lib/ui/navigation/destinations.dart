/// 应用导航结构。
///
/// 8 个目的地与旧版 `src/components/app-shell.tsx` 的 `navigation` 数组一致，
/// 快捷键 `⌘1`–`⌘8` 也沿用同一顺序。
///
/// 移动端只把前 4 项放在底部 Tab Bar，其余进「更多」面板——
/// 这与旧版的 `mobilePrimary = ["/", "/study", "/words", "/add"]` 相同。
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 一个导航目的地的分组。
///
/// **为什么要分组**：8 个目的地平铺时，侧边栏读起来是 8 条等权重的行——
/// 「音标」与「设置」一样大，「初始化」夹在「添加」与「统计」之间。
/// 用户找不到主线，是因为界面没给出主线：今日/复习/单词本是每天用的，
/// 添加/初始化是准备词库时才用的，音标是训练，统计/设置是查阅。
///
/// 分组只改变**呈现**，不改变路由、`⌘1`–`⌘8` 的顺序，也不改变
/// [mobilePrimaryPaths] —— 深链接、书签与测试都不受影响。
enum DestinationGroup {
  /// 无组头的日常主线：今日 / 复习 / 单词本。
  primary(null),

  /// 准备词库：添加 / 初始化。
  library('词库准备'),

  /// 训练：音标。
  training('训练'),

  /// 查阅：统计 / 设置（在侧边栏贴底，在「更多」面板里排最后）。
  reference('查阅');

  new(this.label);

  /// 组标题；为 null 时不渲染组头。
  final String? label;
}

/// 一个导航目的地。
@immutable
class AppDestination {
  /// 创建导航目的地。
  const new({
    required this.path,
    required this.label,
    required this.icon,
    required this.shortcut,
    required this.group,
  });

  /// 路由路径。
  final String path;

  /// 显示名称。
  final String label;

  /// 图标。
  final IconData icon;

  /// `⌘N` 快捷键中对应的数字。
  final int shortcut;

  /// 分组。
  final DestinationGroup group;
}

/// 全部 8 个导航目的地，顺序即快捷键顺序。
const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination(
    path: '/',
    label: '今日',
    icon: LucideIcons.house,
    shortcut: 1,
    group: DestinationGroup.primary,
  ),
  AppDestination(
    path: '/study',
    label: '复习',
    icon: LucideIcons.circlePlay,
    shortcut: 2,
    group: DestinationGroup.primary,
  ),
  AppDestination(
    path: '/words',
    label: '单词本',
    icon: LucideIcons.bookMarked,
    shortcut: 3,
    group: DestinationGroup.primary,
  ),
  AppDestination(
    path: '/phonetics',
    label: '音标',
    icon: LucideIcons.audioLines,
    shortcut: 4,
    group: DestinationGroup.training,
  ),
  AppDestination(
    path: '/add',
    label: '添加',
    icon: LucideIcons.circlePlus,
    shortcut: 5,
    group: DestinationGroup.library,
  ),
  AppDestination(
    path: '/initialize',
    label: '初始化',
    icon: LucideIcons.refreshCw,
    shortcut: 6,
    group: DestinationGroup.library,
  ),
  AppDestination(
    path: '/statistics',
    label: '统计',
    icon: LucideIcons.chartColumn,
    shortcut: 7,
    group: DestinationGroup.reference,
  ),
  AppDestination(
    path: '/settings',
    label: '设置',
    icon: LucideIcons.settings,
    shortcut: 8,
    group: DestinationGroup.reference,
  ),
];

/// 侧边栏里按分组切开的顺序。
///
/// [DestinationGroup.primary] 不渲染组头，其余按这里的顺序渲染标题。
const List<DestinationGroup> sidebarGroupOrder = <DestinationGroup>[
  DestinationGroup.primary,
  DestinationGroup.library,
  DestinationGroup.training,
  DestinationGroup.reference,
];

/// 取出某个分组下的目的地，保持 [appDestinations] 的顺序。
List<AppDestination> destinationsIn(DestinationGroup group) => appDestinations
    .where((destination) => destination.group == group)
    .toList(growable: false);

/// 底部 Tab Bar 上直接展示的目的地路径。
const Set<String> mobilePrimaryPaths = <String>{
  '/',
  '/study',
  '/words',
  '/add',
};

/// 这些路径进入沉浸模式：隐藏侧边栏与底部 Tab Bar。
///
/// 与旧版一致——学习、游戏、配对、音标训练时需要全屏专注。
const Set<String> immersivePaths = <String>{
  '/study',
  '/games',
  '/match',
  '/phonetics',
};

/// 判断给定路径是否应进入沉浸模式。
bool isImmersivePath(String location) {
  if (immersivePaths.contains(location)) return true;
  // 子路径（如 /study/xxx）同样视为沉浸。
  return immersivePaths.any((path) => location.startsWith('$path/'));
}

/// 判断某个目的地是否匹配当前路径（用于高亮）。
bool isDestinationActive(AppDestination destination, String location) {
  if (destination.path == '/') return location == '/';
  return location == destination.path ||
      location.startsWith('${destination.path}/');
}
