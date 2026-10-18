/// 自适应导航外壳：宽屏走侧边栏，窄屏走底部 Tab Bar。
///
/// 断点为 [sidebarBreakpoint]（1024 逻辑像素），与旧版 Tailwind 的 `lg:`
/// 一致。macOS 窗口可自由缩放，两种形态都可能出现；Android 恒为窄屏。
///
/// 沉浸式页面（学习、游戏、配对、音标）不渲染任何导航外壳。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 承载 8 个分支的自适应外壳。
class AdaptiveShell extends StatelessWidget {
  /// 创建外壳。
  const new({required this.navigationShell, super.key});

  /// go_router 的分支导航状态。
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final immersive = isImmersivePath(location);

    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useSidebar = constraints.maxWidth >= sidebarBreakpoint;
          // 沉浸模式**只隐藏窄屏的底部 Tab Bar**，宽屏侧边栏保留。
          //
          // 旧版 `components/app-shell.tsx` 就是这么做的：`isStudyScreen` 只影响
          // `!isStudyScreen && <nav class="... lg:hidden">`（移动端底栏）与底部
          // 内边距，桌面侧边栏 `<aside class="... lg:flex">` 从不隐藏。
          //
          // 早先的实现把两者一起隐藏了，于是在沉浸页上：栈里没有上一页、
          // 侧边栏又不在，用户只能靠页面自己的退出按钮——那个按钮一旦写错
          // （见 `study_page.dart` 的 `_leaveToHome`），整页就没有出路。
          final content = _content();
          // **环境光斑只画一次**。收敛前窄屏的沉浸分支直接返回 `content`，
          // 于是学习页自己画的 `AmbientBackground`（`study_page.dart`）与
          // 游戏页画的（`game_shell.dart`）在宽屏下与外壳画的叠成两层，
          // 光斑颜色被乘了两遍，页面比其它页更“脏”一档。
          if (useSidebar) {
            return AmbientBackground(
              child: _buildWide(context, content, immersive: immersive),
            );
          }
          final shell = immersive ? content : _buildCompact(context, content);
          return AmbientBackground(child: shell);
        },
      ),
    );
  }

  /// 内容区，并保证它有一个 [Material] 祖先。
  ///
  /// **这不是装饰，是必需的**：`TextField`、`Checkbox`、`InkWell`、`Switch`
  /// 等一大票 Material 组件都会向上查找最近的 `Material`，找不到就抛
  /// 「No Material widget found」。而外壳的内容区只有
  /// `AmbientBackground`（`DecoratedBox` + `Stack`），页面若自己没有
  /// `Scaffold` 就没有 `Material` 祖先——添加页正是这样：它的
  /// `ManualEntryForm` 里有 6 个 `TextField`，一进页面就是整屏红字。
  ///
  /// **为什么在调试下才炸**：`debugCheckHasMaterial` 是 `assert`，release
  /// 构建会被剥掉，所以 Web 的 release 端到端测试照样跑通，只有 debug 构建
  /// 会当场报错——这类缺陷只有「让每个页面都有一条真实的路由级测试」才拦得住。
  ///
  /// 用 `MaterialType.transparency`：只登记祖先，不画任何底色，页面自己的
  /// 背景与玻璃层不受影响。
  Widget _content() =>
      Material(type: MaterialType.transparency, child: navigationShell);

  Widget _buildWide(
    BuildContext context,
    Widget content, {
    required bool immersive,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: sidebarWidth,
          child: _Sidebar(navigationShell: navigationShell),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              key: contentCapKey,
              constraints: BoxConstraints(
                maxWidth: immersive
                    ? LexiLayout.immersiveMaxWidth
                    : LexiLayout.pageMaxWidth,
              ),
              // **必须显式撑满**：`Center` 给的是松约束，`Column` 在松约束
              // 下会收缩到最宽子节点的宽度，卡片宽度就跟着内容走而不是跟着
              // 版心走——同一页里两张卡片的宽度会不一样。
              child: SizedBox(width: double.infinity, child: content),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, Widget content) {
    return Column(
      children: <Widget>[
        Expanded(child: content),
        _BottomBar(navigationShell: navigationShell),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 侧边栏（macOS 宽窗口）
// ═══════════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  const new({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Material(
      key: appSidebarKey,
      color: context.lexiColors.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LexiSpace.s20,
          LexiSpace.s24,
          LexiSpace.s16,
          LexiSpace.s16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SidebarBrand(),
            const SizedBox(height: LexiSpace.s24),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: _navigationChildren(context, location),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 侧边栏的分组导航。
  ///
  /// **为什么把「统计 / 设置」也放在滚动区里而不钉在底部**：钉底少一次
  /// 滚动，但窗口最小高度 560、系统字体放大时，钉死的那一组会先把上方的
  /// `Expanded` 挤到 0 再溢出。分组标题已经能表达「这几项不是主线」，
  /// 可滚动的列表在任何字号下都不会溢出。
  List<Widget> _navigationChildren(BuildContext context, String location) {
    final children = <Widget>[];
    for (final group in sidebarGroupOrder) {
      final items = destinationsIn(group);
      if (items.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: LexiSpace.s14));
      }
      children.addAll(_groupChildren(group, items, location));
    }
    return children;
  }

  /// 一个分组：可选的组头 + 组内条目。
  List<Widget> _groupChildren(
    DestinationGroup group,
    List<AppDestination> items,
    String location,
  ) => <Widget>[
    if (group.label != null) _GroupLabel(label: group.label!),
    for (final destination in items)
      _SidebarItem(
        destination: destination,
        active: isDestinationActive(destination, location),
        onTap: () => _goTo(destination),
      ),
  ];

  void _goTo(AppDestination destination) {
    final index = appDestinations.indexOf(destination);
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

/// 分组标题。
class _GroupLabel extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      LexiSpace.s12,
      0,
      LexiSpace.s12,
      LexiSpace.s6,
    ),
    child: Text(
      label,
      style: LexiType.caption.copyWith(
        color: context.lexiColors.quaternaryLabel,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _SidebarBrand extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Icon(LucideIcons.repeat2, color: colors.accent, size: 22),
        const SizedBox(width: LexiSpace.s8),
        Text(
          'LexiLoop',
          style: LexiType.title.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const new({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final AppDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = active ? colors.accentText : colors.secondaryLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s2),
      child: Material(
        color: active
            ? colors.accent.withValues(alpha: LexiTint.tint)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            child: Row(
              children: <Widget>[
                Icon(destination.icon, size: 18, color: foreground),
                const SizedBox(width: LexiSpace.s12),
                Expanded(
                  child: Text(
                    destination.label,
                    style: LexiType.callout.copyWith(
                      color: active ? colors.accentText : colors.label,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (active)
                  Text(
                    '⌘${destination.shortcut}',
                    style: LexiType.caption.copyWith(
                      color: colors.quaternaryLabel,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 底部 Tab Bar（Android 与 macOS 窄窗口）
// ═══════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  const new({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final primary = appDestinations
        .where((d) => mobilePrimaryPaths.contains(d.path))
        .toList(growable: false);
    final overflow = appDestinations
        .where((d) => !mobilePrimaryPaths.contains(d.path))
        .toList(growable: false);
    final overflowActive = overflow.any(
      (d) => isDestinationActive(d, location),
    );

    return Material(
      color: context.lexiColors.card,
      elevation: 4,
      shadowColor: context.lexiColors.borderSubtle,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s8,
            vertical: LexiSpace.s4,
          ),
          child: Row(
            children: <Widget>[
              for (final destination in primary)
                Expanded(
                  child: _BottomBarItem(
                    destination: destination,
                    active: isDestinationActive(destination, location),
                    onTap: () => _goTo(destination),
                  ),
                ),
              Expanded(
                child: _MoreButton(
                  active: overflowActive,
                  onTap: () => _openMoreSheet(context, overflow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goTo(AppDestination destination) {
    final index = appDestinations.indexOf(destination);
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  Future<void> _openMoreSheet(
    BuildContext context,
    List<AppDestination> overflow,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MoreSheet(
        destinations: overflow,
        onSelect: (destination) {
          Navigator.of(sheetContext).pop();
          _goTo(destination);
        },
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const new({
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final AppDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = active ? colors.accentText : colors.tertiaryLabel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(destination.icon, size: 20, color: foreground),
            const SizedBox(height: LexiSpace.s4),
            Text(
              destination.label,
              style: LexiType.caption.copyWith(
                color: foreground,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const new({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = active ? colors.accentText : colors.tertiaryLabel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(LucideIcons.ellipsis, size: 20, color: foreground),
            const SizedBox(height: LexiSpace.s4),
            Text(
              '更多',
              style: LexiType.caption.copyWith(
                color: foreground,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const new({required this.destinations, required this.onSelect});

  final List<AppDestination> destinations;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s12),
        child: LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.xxl),
          showSpecular: true,
          padding: const EdgeInsets.all(LexiSpace.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: LexiSpace.s4,
                  bottom: LexiSpace.s12,
                ),
                child: Text(
                  '更多',
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: LexiSpace.s8,
                crossAxisSpacing: LexiSpace.s8,
                childAspectRatio: 2.6,
                children: <Widget>[
                  // **按分组排序**：底部「更多」里的顺序与侧边栏一致，
                  // 否则同一个应用里「添加」在两处的邻居不同。
                  for (final destination in _sortedByGroup(destinations))
                    _MoreSheetItem(
                      destination: destination,
                      onTap: () => onSelect(destination),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreSheetItem extends StatelessWidget {
  const new({required this.destination, required this.onTap});

  final AppDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;

    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
          child: Row(
            children: <Widget>[
              Icon(destination.icon, size: 17, color: colors.accent),
              const SizedBox(width: LexiSpace.s10),
              Text(
                destination.label,
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按 [sidebarGroupOrder] 给目的地排序，保持组内原有顺序。
List<AppDestination> _sortedByGroup(List<AppDestination> destinations) {
  final sorted = <AppDestination>[];
  for (final group in sidebarGroupOrder) {
    for (final destination in destinations) {
      if (destination.group == group) sorted.add(destination);
    }
  }
  return sorted;
}
