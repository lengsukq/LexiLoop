/// 应用路由配置。
///
/// 8 个分支与 [appDestinations] 一一对应，用 `StatefulShellRoute.indexedStack`
/// 保持各 Tab 的滚动位置与页面状态——这是旧版多页面切换时不具备的体验。
///
/// **子路由与独立路由的分界**：
/// - 需要保留外壳（侧边栏 / 底部 Tab）的页面挂在分支下，例如词条详情；
/// - 需要独占屏幕的向导类页面（CSV 导入）挂在顶层，避免用户在多步流程里
///   被导航分散注意力。
///
/// **专项学习模式走 query 而非独立路径**：8 种模式共用同一个会话页与
/// 同一套出题逻辑，拆成 8 条路径会让 `immersivePaths`、分支高亮与返回栈
/// 各自多出 8 个分支。`/study?mode=WRONG_WORDS` 既是旧版地址，也是首页
/// 队列卡片的落点。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/add_page.dart';
import 'package:lexiloop/features/add/article_page.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/features/games/games_page.dart';
import 'package:lexiloop/features/import/import_page.dart';
import 'package:lexiloop/features/initialize/initialize_page.dart';
import 'package:lexiloop/features/match/match_page.dart';
import 'package:lexiloop/features/phonetics/phonetics_page.dart';
import 'package:lexiloop/features/settings/settings_page.dart';
import 'package:lexiloop/features/statistics/statistics_page.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/features/word_detail/word_detail_page.dart';
import 'package:lexiloop/features/words/words_page.dart';
import 'package:lexiloop/ui/adaptive_shell.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';

/// 全局路由实例。
final GoRouter appRouter = createAppRouter();

/// 顶层路由的版心包装。
///
/// 这四条路由不套 `AdaptiveShell`，因此拿不到外壳在内容区做的限宽。
/// 包装放在这里而不是各页自己写：**漏掉一页就是那一页在宽窗口下被拉长**，
/// 而「哪几页是顶层路由」这件事只有这张表说得清。
Widget _capped(Widget page, {double maxWidth = LexiLayout.immersiveMaxWidth}) =>
    // 顶层路由拿不到外壳画的背景与版心，所以这两件事都由这里补上。
    // 背景只在这里画一次：页面自己再画一层会变成双层光斑。
    AmbientBackground(
      child: ContentWidthCap(maxWidth: maxWidth, child: page),
    );

/// 构造一份新的路由表。
///
/// 导出成函数而不是只用全局单例：GoRouter 持有匹配结果与导航栈，
/// 跨用例复用会让路由断言依赖执行顺序，测试必须每个用例拿一份干净的。
///
/// [initialLocation] 允许测试直接落在目标路由上，不必先渲染首页——
/// 首页会牵出 AI 建议等与被测行为无关的异步工作。
GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: csvImportPath,
        // 导入页有 5 列表格，版心用普通页的宽度：840 会把「问题」列压到
        // 只剩省略号（见 `import_preview_table.dart` 的列宽分配）。
        builder: (context, state) =>
            _capped(const ImportPage(), maxWidth: LexiLayout.pageMaxWidth),
      ),
      GoRoute(
        path: articlePath,
        builder: (context, state) => _capped(const ArticlePage()),
      ),
      // 小游戏与配对不在主导航里（它们是「独立模式，不占用今日复习队列」），
      // 从首页的「趣味训练」进入，因此是顶层路由、不套外壳。
      GoRoute(
        path: gamesPath,
        builder: (context, state) =>
            _capped(GamesPage(initialMode: state.uri.queryParameters['mode'])),
      ),
      GoRoute(
        path: matchPath,
        builder: (context, state) => _capped(const MatchPage()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AdaptiveShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          for (final destination in appDestinations)
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: destination.path,
                  builder: (context, state) => pageForDestination(
                    destination,
                    studyModeWire: state.uri.queryParameters['mode'],
                  ),
                  routes: _subRoutesFor(destination),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// 导航目的地 → 页面。
///
/// 导出成公开函数而不是私有分支，是为了让
/// `test/app/destination_pages_test.dart` 能遍历 [appDestinations]
/// 逐个断言「每个目的地都真的有页面」——这是本文件唯一无法靠类型系统
/// 保证的事情（`path` 是字符串）。
///
/// **未知路径抛 [StateError] 而不是渲染一个兜底页**：兜底页会让「新加了
/// 目的地却忘了接线」表现为一个能正常打开的空页面，而抛错会在测试里
/// 立刻暴露。旧版没有这层保护，占位组件被当成已完成页面用了很久。
Widget pageForDestination(AppDestination destination, {String? studyModeWire}) {
  return switch (destination.path) {
    '/' => const DashboardPage(),
    '/add' => const AddPage(),
    '/games' => const GamesPage(),
    '/initialize' => const InitializePage(),
    '/match' => const MatchPage(),
    '/phonetics' => const PhoneticsPage(),
    '/words' => const WordsPage(),
    '/settings' => const SettingsPage(),
    '/statistics' => const StatisticsPage(),
    '/study' => StudyPage(mode: studyModeOf(studyModeWire)),
    _ => throw StateError(
      '导航目的地 ${destination.path} 没有对应页面：'
      ' 请在 pageForDestination 里补一个分支。',
    ),
  };
}

/// 把 `/study?mode=` 的取值解析成 [StudyMode]。
///
/// **必须兜底而不是抛错**：首页「开始学习」、导航 `⌘2` 与旧书签都直接
/// 落到裸 `/study`，一个拼错的 `mode` 若抛异常，整页会白屏且没有返回
/// 入口。兜底到 [StudyMode.daily] 也正是旧版 `study` 页的行为。
StudyMode studyModeOf(String? wire) {
  if (wire == null) return StudyMode.daily;
  return wireLookup(StudyMode.values, wire) ?? StudyMode.daily;
}

/// 子路由。
///
/// 词条详情是唯一有子路由的页面：它从词库列表进入，返回时应回到原列表位置，
/// 因此必须留在同一个分支里（顶层路由会重置分支状态）。
List<RouteBase> _subRoutesFor(AppDestination destination) {
  if (destination.path != '/words') return const <RouteBase>[];
  return <RouteBase>[
    GoRoute(
      path: ':id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        final child = id == null
            ? const _InvalidWordIdPage()
            : WordDetailPage(wordId: id);
        return LexiMotion.pushPage<void>(key: state.pageKey, child: child);
      },
    ),
  ];
}

/// 路径参数不是整数时的兜底页。
///
/// 直接抛异常会让整页白屏且没有返回入口；这里给出可读提示。
class _InvalidWordIdPage extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('词条')),
    body: const Center(child: Text('词条 ID 无效')),
  );
}
