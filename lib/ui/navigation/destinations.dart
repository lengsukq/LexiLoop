/// 导航目的地定义：4 个常驻主频道 + 二级功能路由。
///
/// **移动端优先（Mobile-First）的 4-Tab 导航收敛**：
/// 遵循 Apple HIG `tab-bars.md` *“Avoid overflow tabs”* 准则，移动端底部栏
/// 不再塞入「更多（`...`）」二级弹窗，而是收敛为 4 个核心常驻频道：
/// 1. **今日 (`/`)**：每日复习主入口、学习概览与精选专项练习；
/// 2. **单词本 (`/words`)**：无限滚动词库、搜索筛选、快速加词与后台补全状态；
/// 3. **统计 (`/statistics`)**：记忆热力图、掌握度漏斗与复习负荷预测；
/// 4. **设置 (`/settings`)**：复习策略、发音、AI/词典源、备份与同步。
///
/// 动作型与沉浸式页面（`复习 /study`、`添加 /add`、`内容补全 /initialize`、
/// `音标 /phonetics`）作为二级路由保留在导航树中，支持深链与快捷键直达。
library;

import 'package:flutter/widgets.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 桌面侧边栏容器的稳定 Key（供自适应布局测试定位）。
const Key appSidebarKey = Key('app-sidebar');

/// 移动端底部导航栏容器的稳定 Key。
const Key appBottomBarKey = Key('app-bottom-bar');

/// 目的地所属的导航分组。
enum DestinationGroup {
  /// 核心学习与词库。
  learning(null),

  /// 词库扩展与工具。
  library('词库管理'),

  /// 统计与系统设置。
  reference('数据与偏好');

  new(this.label);

  /// 侧边栏分组小标题；首组为 `null` 不显示标题。
  final String? label;
}

/// 侧边栏分组渲染顺序。
const List<DestinationGroup> sidebarGroupOrder = <DestinationGroup>[
  DestinationGroup.learning,
  DestinationGroup.library,
  DestinationGroup.reference,
];

/// 单个导航目的地定义。
class AppDestination {
  /// 创建导航目的地。
  const new({
    required this.path,
    required this.label,
    required this.icon,
    required this.shortcut,
    required this.group,
    this.immersive = false,
  });

  /// 路由路径。
  final String path;

  /// 导航展示名称。
  final String label;

  /// 导航图标。
  final IconData icon;

  /// `⌘1`–`⌘8` 快捷键序号（从 1 开始）。
  final int shortcut;

  /// 侧边栏所属分组。
  final DestinationGroup group;

  /// 是否在窄屏下隐藏底部导航栏（沉浸式全屏页面）。
  final bool immersive;
}

/// 路由分支完整目的地表（保持 `⌘1`–`⌘8` 快捷键序号与分支索引稳定）。
const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination(
    path: homePath,
    label: '今日',
    icon: LucideIcons.sparkles,
    shortcut: 1,
    group: DestinationGroup.learning,
  ),
  AppDestination(
    path: studyPath,
    label: '复习',
    icon: LucideIcons.graduationCap,
    shortcut: 2,
    group: DestinationGroup.learning,
    immersive: true,
  ),
  AppDestination(
    path: wordsPath,
    label: '单词本',
    icon: LucideIcons.bookOpen,
    shortcut: 3,
    group: DestinationGroup.learning,
  ),
  AppDestination(
    path: addPath,
    label: '添加',
    icon: LucideIcons.circlePlus,
    shortcut: 4,
    group: DestinationGroup.library,
  ),
  AppDestination(
    path: initializePath,
    label: '内容补全',
    icon: LucideIcons.wandSparkles,
    shortcut: 5,
    group: DestinationGroup.library,
  ),
  AppDestination(
    path: phoneticsPath,
    label: '音标',
    icon: LucideIcons.volume2,
    shortcut: 6,
    group: DestinationGroup.library,
    immersive: true,
  ),
  AppDestination(
    path: statisticsPath,
    label: '统计',
    icon: LucideIcons.chartColumn,
    shortcut: 7,
    group: DestinationGroup.reference,
  ),
  AppDestination(
    path: settingsPath,
    label: '设置',
    icon: LucideIcons.settings,
    shortcut: 8,
    group: DestinationGroup.reference,
  ),
];

/// 移动端底部 4-Tab 常驻主目的地（今日 / 单词本 / 统计 / 设置）。
final List<AppDestination> mobilePrimaryDestinations = <AppDestination>[
  appDestinations[0],
  appDestinations[2],
  appDestinations[6],
  appDestinations[7],
];

/// 取出某个分组下的主导航目的地（用于桌面侧边栏展示 4 个核心频道）。
List<AppDestination> destinationsIn(DestinationGroup group) =>
    mobilePrimaryDestinations
        .where((destination) => destination.group == group)
        .toList(growable: false);

/// 判断当前路由路径是否为沉浸式窄版心路径（窄屏隐藏底部栏，宽屏使用 `immersiveMaxWidth`）。
bool isImmersivePath(String location) {
  for (final destination in appDestinations) {
    if (destination.immersive && _matchesPath(destination.path, location)) {
      return true;
    }
  }
  return location.startsWith(gamesPath) || location.startsWith(matchPath);
}

/// 判断目的地在当前 [location] 下是否处于激活态。
///
/// 在「添加 (`/add`)」或「内容补全 (`/initialize`)」子流程中，归属到「单词本 (`/words`)」高亮。
bool isDestinationActive(AppDestination destination, String location) {
  if (destination.path == wordsPath &&
      (location.startsWith(addPath) || location.startsWith(initializePath))) {
    return true;
  }
  return _matchesPath(destination.path, location);
}

bool _matchesPath(String base, String location) {
  if (base == '/') return location == '/';
  return location == base || location.startsWith('$base/');
}
