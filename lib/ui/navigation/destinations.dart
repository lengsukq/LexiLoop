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

/// 一个导航目的地。
@immutable
class AppDestination {
  /// 创建导航目的地。
  const new({
    required this.path,
    required this.label,
    required this.icon,
    required this.shortcut,
  });

  /// 路由路径。
  final String path;

  /// 显示名称。
  final String label;

  /// 图标。
  final IconData icon;

  /// `⌘N` 快捷键中对应的数字。
  final int shortcut;
}

/// 全部 8 个导航目的地，顺序即快捷键顺序。
const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination(path: '/', label: '今日', icon: LucideIcons.house, shortcut: 1),
  AppDestination(
    path: '/study',
    label: '复习',
    icon: LucideIcons.circlePlay,
    shortcut: 2,
  ),
  AppDestination(
    path: '/words',
    label: '单词本',
    icon: LucideIcons.bookMarked,
    shortcut: 3,
  ),
  AppDestination(
    path: '/phonetics',
    label: '音标',
    icon: LucideIcons.audioLines,
    shortcut: 4,
  ),
  AppDestination(
    path: '/add',
    label: '添加',
    icon: LucideIcons.circlePlus,
    shortcut: 5,
  ),
  AppDestination(
    path: '/initialize',
    label: '初始化',
    icon: LucideIcons.refreshCw,
    shortcut: 6,
  ),
  AppDestination(
    path: '/statistics',
    label: '统计',
    icon: LucideIcons.chartColumn,
    shortcut: 7,
  ),
  AppDestination(
    path: '/settings',
    label: '设置',
    icon: LucideIcons.settings,
    shortcut: 8,
  ),
];

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
