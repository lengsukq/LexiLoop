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
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

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

    return LayoutBuilder(
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
        if (useSidebar) {
          return AmbientBackground(child: _buildWide(context, content));
        }
        if (immersive) return content;
        return AmbientBackground(child: _buildCompact(context, content));
      },
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

  Widget _buildWide(BuildContext context, Widget content) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: sidebarWidth,
          child: _Sidebar(navigationShell: navigationShell),
        ),
        Expanded(child: content),
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

    return Padding(
      padding: const EdgeInsets.all(LexiSpace.s12),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
        showSpecular: true,
        showEdge: true,
        padding: const EdgeInsets.all(LexiSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SidebarBrand(),
            const SizedBox(height: LexiSpace.s20),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  for (final destination in appDestinations)
                    _SidebarItem(
                      destination: destination,
                      active: isDestinationActive(destination, location),
                      onTap: () => _goTo(destination),
                    ),
                ],
              ),
            ),
            const _SidebarFooter(),
          ],
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
}

class _SidebarBrand extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Icon(Icons.loop_rounded, color: colors.accent, size: 22),
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
    final foreground = active ? colors.accent : colors.secondaryLabel;

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
                      color: active ? colors.accent : colors.label,
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

/// 侧边栏底部状态卡。
///
/// **注意**：旧版这里写的是「自托管运行中」加绿色呼吸点。纯本地版没有
/// 自托管概念，那行文案是错误信息，此处改为反映本地数据库状态。
class _SidebarFooter extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LiquidGlass(
          level: GlassLevel.subtle,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s10,
            vertical: LexiSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.storage_rounded, size: 13, color: colors.success),
              const SizedBox(width: LexiSpace.s6),
              Expanded(
                child: Text(
                  '本地数据库',
                  style: LexiType.caption.copyWith(
                    color: colors.secondaryLabel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.auto_awesome, size: 12, color: colors.accent),
              const SizedBox(width: LexiSpace.s4),
              Text(
                'FSRS',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 两侧文本都要可收缩：侧边栏宽度固定，系统字体放大时
              // 不定宽文本会直接溢出。
              Flexible(
                child: Text(
                  'LexiLoop v1.0',
                  overflow: TextOverflow.ellipsis,
                  style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              Flexible(
                child: Text(
                  '⌘1-8 快捷切换',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
                ),
              ),
            ],
          ),
        ),
      ],
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LexiSpace.s12,
          0,
          LexiSpace.s12,
          LexiSpace.s8,
        ),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(LexiRadius.xl),
          showSpecular: true,
          showEdge: true,
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s6,
            vertical: LexiSpace.s6,
          ),
          // InkWell 需要 Material 祖先才能绘制涟漪；LiquidGlass 只提供
          // DecoratedBox，因此在此显式包一层透明 Material。
          child: Material(
            type: MaterialType.transparency,
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
    final foreground = active ? colors.accent : colors.tertiaryLabel;

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
    final foreground = active ? colors.accent : colors.tertiaryLabel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.more_horiz_rounded, size: 20, color: foreground),
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
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: <Widget>[
                  for (final destination in destinations)
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
