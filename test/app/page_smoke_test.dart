/// 每个页面的**路由级冒烟 + 自适应**测试。
///
/// **它守的是什么**：
///
/// 1. `Material` 祖先。页面在自己的 widget 测试里通常被塞进
///    `MaterialApp(home: Scaffold(body: Page()))`，于是 `Scaffold` 提供了
///    `Material` 祖先；而真实路由里页面挂在 `AdaptiveShell` 的内容区。页面若
///    自己不提供 `Material`，`TextField` / `Checkbox` / `InkWell` 就会向上找
///    很远——添加页当初要找 110 层以上才碰到一个，而 `debugCheckHasMaterial`
///    会在 `LookupBoundary` 处截断查找。
///
///    这类缺陷的麻烦之处是 `debugCheckHasMaterial` 是 `assert`：release 构建
///    会剥掉它，所以 Web 的 release 端到端测试照样全绿，只有 debug 构建会
///    整屏红字。因此这组用例**只从真实路由进入每个页面**。
///
/// 2. 自适应。每个页面在 4 种宽度下各渲染一遍：手机竖屏 360、平板 700、
///    桌面 1000 与宽桌面 1440。布局溢出（`RenderFlex overflowed`）在测试里
///    是构建期异常，会被 `takeException()` 抓住——这正是「各个页面的设计都
///    要自适应」的可执行定义。
///
/// **诚实说明**：报告里那次添加页红屏在本机复现不出来（同一份代码、debug
/// 构建、真实应用根、宽窄两种宽度都不报错），所以这里不能声称「复现了那个
/// 缺陷」。它守的是**同一类**问题：任何页面在真实路由下构建期抛异常都会被
/// 抓住。外壳内容区的 `Material`（`adaptive_shell.dart` 的 `_content()`）
/// 让页面不再依赖远处的祖先，这才是那次红屏的结构性修法。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
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

/// 自适应要覆盖的宽度。
///
/// 360 是主流手机竖屏下限；700 是平板竖屏；1000 刚过侧边栏断点（1024）；
/// 1440 是宽桌面。断点两侧都要有，否则「过断点时布局重排」这类缺陷测不到。
const Map<String, double> widths = <String, double>{
  '手机 360': 360,
  '平板 700': 700,
  '桌面 1000': 1000,
  '宽桌面 1440': 1440,
};

/// 视口高度。
///
/// **必须覆盖窗口的最小高度**（`main.dart` 里限制的 560）：高度比宽度更容易
/// 被忽略，而溢出恰恰在这里发生——固定高度的卡片、吸底条、页头叠在一起，
/// 840 高时宽宽松松，560 高时就把列表挤成负空间。此前只测过一个 900，
/// 等于把「最小窗口」这一档留空了。
const Map<String, double> heights = <String, double>{
  '常规 900': 900,
  '最小 560': 560,
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 从真实路由打开一个地址并渲染若干帧。
  ///
  /// 不用 `pumpAndSettle`：若干页面停在带无限动画的加载态，会一直等到超时。
  /// 这里要抓的是构建期异常（缺 `Material`、布局溢出都是构建期抛的），
  /// 几帧足够。
  Future<void> pumpRoute(
    WidgetTester tester,
    String location,
    double width, {
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final router = createAppRouter(initialLocation: location);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          // 平台通道插件在测试进程里不可用，三个替身缺一不可。
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
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      tester.takeException(),
      isNull,
      reason:
          '$location 在 $width×$height 下抛异常。\n'
          '若是 `RenderFlex overflowed`，说明该页在这一档尺寸下不自适应；\n'
          '若是 `No Material widget found`，说明它依赖了远处的祖先。',
    );
  }

  // 宽度矩阵用常规高度跑全量；最小高度再单独跑一遍全量——
  // 两个维度都铺开会让用例数乘到 96 条，而高度问题与宽度基本正交，
  // 用「全量 × 最小高度 + 全量 × 常规高度」就能覆盖。
  for (final path in allRoutes) {
    for (final entry in widths.entries) {
      testWidgets('$path 在 ${entry.key} 下能渲染且无异常', (tester) async {
        await pumpRoute(tester, path, entry.value);
      });
    }
    testWidgets('$path 在最小窗口 360×560 下能渲染且无异常', (tester) async {
      await pumpRoute(tester, path, 360, height: heights['最小 560']!);
    });
    testWidgets('$path 在最小窗口 1280×560 下能渲染且无异常', (tester) async {
      await pumpRoute(tester, path, 1280, height: heights['最小 560']!);
    });
  }

  testWidgets('添加页的输入框在真实路由下有 Material 祖先', (tester) async {
    // 这条直接钉住那个红屏：添加页自己没有 Scaffold，
    // 全靠外壳内容区的 Material 兜底。
    await pumpRoute(tester, '/add', 1200);
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('窄屏走底部 Tab（带「更多」），宽屏走侧边栏', (tester) async {
    // 断点两侧的导航形态必须真的不同，否则「自适应」只是没崩而已。
    // 底部 Tab 把超出 4 个的目的地收进「更多」，侧边栏则全部平铺——
    // 用「更多」的有无来区分两种形态。
    await pumpRoute(tester, '/', 420);
    expect(find.text('更多'), findsOneWidget);

    await pumpRoute(tester, '/', 1200);
    expect(find.text('更多'), findsNothing);
    // 用侧边栏的稳定 key 把断言限定在导航里：「今日」这类标签在页面正文里
    // 也会出现，按材质找会随设计调整而失效。
    for (final destination in appDestinations) {
      expect(
        find.descendant(
          of: find.byKey(appSidebarKey),
          matching: find.text(destination.label),
        ),
        findsWidgets,
        reason: '宽屏侧边栏应当平铺出全部目的地：${destination.label}',
      );
    }
  });
}
