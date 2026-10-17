/// 版面宽度的守卫测试。
///
/// **它守的是什么**：1440 逻辑像素的窗口里，正文列不应当被拉成一条长带。
/// 收敛前全仓只有 `games/widgets/game_shell.dart` 一处限宽，其余页面都是
/// `ListView(padding: EdgeInsets…)` 直接铺满内容区——统计页的一行 6 个数字
/// 因此横跨 1184 像素，卡片里的文字却只占左边 200 像素。
///
/// 这条守卫断言的是**渲染结果**而不是源码里的字面量：侧边栏宽度、栏距、
/// `Center` 的参与都会改变最终宽度，只有量出来的那个数才是用户看到的。
///
/// **反向验证**：把 `AdaptiveShell._buildWide` 里的 `ConstrainedBox` 去掉，
/// 1440 一下的用例会以「实际 1184 > 上限 1040」失败。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../services/audio/audio_fakes.dart';

/// 逐个走一遍的地址：8 个主导航目的地 + 4 个顶层向导路由。
final List<String> allRoutes = <String>[
  for (final destination in appDestinations) destination.path,
  csvImportPath,
  articlePath,
  gamesPath,
  matchPath,
];

/// 版心更窄（`LexiLayout.immersiveMaxWidth`）的路由。
///
/// 两类：外壳里的沉浸页（学习 / 游戏 / 配对 / 音标，屏幕上一个焦点），
/// 以及 `/article`——它是单列向导，宽到 1040 只会让正文行更长。
/// `/import` 不在此列：它有一张 5 列表格，840 会把「问题」列压成省略号。
const Set<String> immersiveWidthRoutes = <String>{
  '/study',
  '/games',
  '/match',
  '/phonetics',
  '/article',
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 以给定窗口宽度渲染一条路由，返回内容区上限节点的实际尺寸。
  ///
  /// 断点以下（窄屏分支）没有这个节点，返回 `null`——那正是「版心不参与」
  /// 的表现，测试据此断言而不是靠猜。
  Future<Size?> pumpAndMeasure(
    WidgetTester tester,
    String location,
    double width,
  ) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = createAppRouter(initialLocation: location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
          audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
          studyClockFactoryProvider.overrideWithValue(
            () => StudyClock(
              now: () => tester.binding.clock.now().millisecondsSinceEpoch,
            ),
          ),
        ],
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    for (var i = 0; i < 8; i += 1) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    final finder = find.byKey(contentCapKey);
    if (finder.evaluate().isEmpty) return null;
    return tester.getSize(finder);
  }

  group('宽窗口下的正文列', () {
    for (final path in allRoutes) {
      testWidgets('$path 在 1440 宽下不超过版心上限', (tester) async {
        // 侧边栏断点以上，走的是限宽分支。
        final size = await pumpAndMeasure(tester, path, 1440);
        expect(size, isNotNull, reason: '$path 在 1440 宽下没有内容区上限节点');
        final cap = immersiveWidthRoutes.contains(path)
            ? LexiLayout.immersiveMaxWidth
            : LexiLayout.pageMaxWidth;
        expect(
          size!.width,
          lessThanOrEqualTo(cap + 0.5),
          reason: '$path 在 1440 宽下正文列 ${size.width} 超过了 $cap',
        );
        // 上限必须真的生效（而不是内容自己缩到了更窄）：
        // 内容区可用 1440 − 256 侧边栏 = 1184 > 1040，所以应当顶到上限。
        expect(
          size.width,
          closeTo(cap, 0.5),
          reason: '$path 的版心应当顶到上限 $cap，实际 ${size.width}',
        );
      });
    }

    testWidgets('正文列在内容区里居中，而不是贴着侧边栏', (tester) async {
      final size = await pumpAndMeasure(tester, '/statistics', 1440);
      expect(size, isNotNull);
      final rect = tester.getRect(find.byKey(contentCapKey));
      // 内容区从侧边栏右缘（256）到窗口右缘（1440）。
      const contentLeft = sidebarWidth;
      const contentRight = 1440.0;
      final leftGap = rect.left - contentLeft;
      final rightGap = contentRight - rect.right;
      expect(
        (leftGap - rightGap).abs(),
        lessThan(1),
        reason: '左留白 $leftGap 与右留白 $rightGap 不等，正文列没有居中',
      );
      expect(size!.width, closeTo(LexiLayout.pageMaxWidth, 0.5));
    });

    testWidgets('窄于上限时版心不参与布局，页面铺满可用宽度', (tester) async {
      // 900 < 侧边栏断点 1024，走的是窄屏分支：没有上限节点。
      // 这条用例守的是「别把上限做成全局的强行收窄」——那会让小窗口
      // 里的正文列凭空变窄、两侧留出无用的空白。
      final size = await pumpAndMeasure(tester, '/statistics', 900);
      expect(size, isNull, reason: '窄屏分支不该出现上限节点（可用宽度本来就小于上限）');
    });
  });
}
