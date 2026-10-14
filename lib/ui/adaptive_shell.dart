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

/// 承载 8 个分支的自适应外壳。
class AdaptiveShell extends StatelessWidget {
  /// 创建外壳。
  const new({required this.navigationShell, super.key});

  /// go_router 的分支导航状态。
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    if (isImmersivePath(location)) {
      return navigationShell;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSidebar = constraints.maxWidth >= sidebarBreakpoint;
        return AmbientBackground(
          child: useSidebar ? _buildWide(context) : _buildCompact(context),
        );
      },
    );
  }

  Widget _buildWide(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: sidebarWidth,
          child: _Sidebar(navigationShell: navigationShell),
        ),
        Expanded(child: navigationShell),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(child: navigationShell),
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
      padding: const EdgeInsets.all(12),
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
        showSpecular: true,
        showEdge: true,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _SidebarBrand(),
            const SizedBox(height: 20),
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
        const SizedBox(width: 8),
        Text(
          'LexiLoop',
          style: TextStyle(
            color: colors.label,
            fontSize: 17,
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: active
            ? colors.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(destination.icon, size: 18, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    style: TextStyle(
                      color: active ? colors.accent : colors.label,
                      fontSize: 14.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (active)
                  Text(
                    '⌘${destination.shortcut}',
                    style: TextStyle(
                      color: colors.quaternaryLabel,
                      fontSize: 10,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(Icons.storage_rounded, size: 13, color: colors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '本地数据库',
                  style: TextStyle(
                    color: colors.secondaryLabel,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.auto_awesome, size: 12, color: colors.accent),
              const SizedBox(width: 3),
              Text(
                'FSRS',
                style: TextStyle(color: colors.tertiaryLabel, fontSize: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // 两侧文本都要可收缩：侧边栏宽度固定，系统字体放大时
              // 不定宽文本会直接溢出。
              Flexible(
                child: Text(
                  'LexiLoop v1.0',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.tertiaryLabel, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '⌘1-8 快捷切换',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: colors.tertiaryLabel, fontSize: 11),
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(LexiRadius.xl),
          showSpecular: true,
          showEdge: true,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(destination.icon, size: 20, color: foreground),
            const SizedBox(height: 3),
            Text(
              destination.label,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.more_horiz_rounded, size: 20, color: foreground),
            const SizedBox(height: 3),
            Text(
              '更多',
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
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
        padding: const EdgeInsets.all(12),
        child: LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.xxl),
          showSpecular: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  '更多',
                  style: TextStyle(
                    color: colors.secondaryLabel,
                    fontSize: 12,
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
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Icon(destination.icon, size: 17, color: colors.accent),
              const SizedBox(width: 10),
              Text(
                destination.label,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 14,
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
