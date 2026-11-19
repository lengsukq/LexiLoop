/// 自适应导航外壳：宽屏走侧边栏，窄屏走 4-Tab 底部导航栏。
///
/// 断点为 [sidebarBreakpoint]（1024 逻辑像素）。
/// 移动端遵循 Apple HIG 4-Tab 原则（今日 / 单词本 / 统计 / 设置），彻底移除「更多」弹窗；
/// 沉浸式页面（学习、游戏、配对、音标）在窄屏下收起底部导航栏以专注当前任务。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 承载主导航与沉浸分支的自适应外壳。
class AdaptiveShell extends StatelessWidget {
  /// 创建外壳。
  const new({required this.navigationShell, super.key});

  /// go_router 的分支导航状态。
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final immersive = isImmersivePath(location);

    final shell = Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useSidebar = constraints.maxWidth >= sidebarBreakpoint;
          final content = _content();
          if (useSidebar) {
            return AmbientBackground(
              child: _buildWide(context, content, immersive: immersive),
            );
          }
          final body = immersive ? content : _buildCompact(context, content);
          return AmbientBackground(child: body);
        },
      ),
    );
    if (location != studyPath) return shell;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (!context.mounted) return false;
        GoRouter.of(context).go(homePath);
        return true;
      },
      child: shell,
    );
  }

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
// 侧边栏（宽窗口）
// ═══════════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  const new({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s8,
        LexiSpace.s8,
        LexiSpace.s4,
        LexiSpace.s8,
      ),
      child: LiquidGlass(
        key: appSidebarKey,
        borderRadius: BorderRadius.circular(LexiRadius.xxl),
        showSpecular: true,
        showEdge: true,
        showShadow: true,
        padding: const EdgeInsets.fromLTRB(
          LexiSpace.s20,
          LexiSpace.s24,
          LexiSpace.s16,
          LexiSpace.s16,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _SidebarBrand(),
              const SizedBox(height: LexiSpace.s24),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: _navigationChildren(location),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _navigationChildren(String location) {
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
    LexiHaptics.selection();
    final index = appDestinations.indexOf(destination);
    navigationShell.goBranch(index, initialLocation: true);
  }
}

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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: AnimatedContainer(
            duration: LexiMotion.quick,
            curve: LexiMotion.spring,
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s12,
              vertical: LexiSpace.s10,
            ),
            decoration: BoxDecoration(
              color: active
                  ? colors.accent.withValues(alpha: LexiTint.tint)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(LexiRadius.md),
              border: Border.all(
                color: active
                    ? colors.accent.withValues(alpha: LexiTint.border)
                    : Colors.transparent,
              ),
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
// 底部 4-Tab 导航栏（移动端窄屏）
// ═══════════════════════════════════════════════════════════════

class _BottomBar extends StatelessWidget {
  const new({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s8,
        LexiSpace.s4,
        LexiSpace.s8,
        LexiSpace.s8,
      ),
      child: LiquidGlass(
        key: appBottomBarKey,
        level: GlassLevel.elevated,
        borderRadius: BorderRadius.circular(LexiRadius.xxl),
        showSpecular: true,
        showShadow: true,
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s8,
          vertical: LexiSpace.s4,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Row(
              children: <Widget>[
                for (final destination in mobilePrimaryDestinations)
                  Expanded(
                    child: _BottomBarItem(
                      destination: destination,
                      active: isDestinationActive(destination, location),
                      onTap: () => _goTo(destination),
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
    LexiHaptics.selection();
    final index = appDestinations.indexOf(destination);
    navigationShell.goBranch(index, initialLocation: true);
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
            AnimatedContainer(
              duration: LexiMotion.quick,
              curve: LexiMotion.spring,
              padding: const EdgeInsets.symmetric(
                horizontal: LexiSpace.s14,
                vertical: LexiSpace.s2,
              ),
              decoration: BoxDecoration(
                color: active
                    ? colors.accent.withValues(alpha: LexiTint.tint)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(LexiRadius.pill),
              ),
              child: Icon(destination.icon, size: 20, color: foreground),
            ),
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
