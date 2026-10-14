/// 应用路由配置。
///
/// 8 个分支与 [appDestinations] 一一对应，用 `StatefulShellRoute.indexedStack`
/// 保持各 Tab 的滚动位置与页面状态——这是旧版多页面切换时不具备的体验。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/features/placeholder/placeholder_page.dart';
import 'package:lexiloop/ui/adaptive_shell.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';

/// 全局路由实例。
final GoRouter appRouter = _createRouter();

GoRouter _createRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          for (final destination in appDestinations)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: destination.path,
                  builder: (context, state) => _pageFor(destination),
                  routes: _subRoutesFor(destination),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

Widget _pageFor(AppDestination destination) {
  if (destination.path == '/') return const DashboardPage();
  return PlaceholderPage(destination: destination);
}

/// 子路由。
///
/// 目前仅有单词详情页需要；其余页面的子路由在对应阶段补入。
List<RouteBase> _subRoutesFor(AppDestination destination) {
  return const <RouteBase>[];
}
