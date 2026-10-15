/// 每个页面的**路由级冒烟测试**。
///
/// **它守的是什么**：页面在自己的 widget 测试里通常被塞进
/// `MaterialApp(home: Scaffold(body: Page()))`，于是 `Scaffold` 提供了
/// `Material` 祖先；而真实路由里页面挂在 `AdaptiveShell` 的内容区，只有
/// `AmbientBackground`（`DecoratedBox` + `Stack`）。页面若自己不提供
/// `Material`，`TextField` / `Checkbox` / `InkWell` 就会向上找很远——
/// 添加页当初要找 110 层以上才碰到一个，而 `debugCheckHasMaterial` 会在
/// `LookupBoundary` 处截断查找。
///
/// 这类缺陷的麻烦之处是 `debugCheckHasMaterial` 是 `assert`：release 构建
/// 会剥掉它，所以 Web 的 release 端到端测试照样全绿，只有 debug 构建会
/// 整屏红字。因此这组用例**只从真实路由进入每个页面**，断言「渲染出来了、
/// 没有异常」，宽窄两种宽度各跑一遍。
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

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 从真实路由打开一个地址并渲染若干帧。
  ///
  /// 不用 `pumpAndSettle`：若干页面停在带无限动画的加载态，会一直等到超时。
  /// 这里要抓的是构建期异常（缺 `Material` 就是构建期抛的），几帧足够。
  Future<void> pumpRoute(
    WidgetTester tester,
    String location, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
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
      reason: '$location 渲染时抛异常（多半是缺 Material 祖先）',
    );
  }

  // 8 个主导航目的地 + 3 个顶层向导路由，逐个走一遍。
  for (final destination in appDestinations) {
    testWidgets('${destination.path} 能渲染且无异常', (tester) async {
      await pumpRoute(tester, destination.path);
    });
  }

  for (final path in <String>[
    csvImportPath,
    articlePath,
    gamesPath,
    matchPath,
  ]) {
    testWidgets('$path 能渲染且无异常', (tester) async {
      await pumpRoute(tester, path);
    });
  }

  testWidgets('添加页的输入框在真实路由下有 Material 祖先', (tester) async {
    // 这条直接钉住那个红屏：添加页自己没有 Scaffold，
    // 全靠外壳内容区的 Material 兜底。
    await pumpRoute(tester, '/add');
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('窄屏下每个页面也能渲染', (tester) async {
    // 自适应要求：窄屏走底部 Tab 布局，页面不能因为宽度变化而崩。
    for (final path in <String>[
      '/',
      '/words',
      '/add',
      '/statistics',
      '/settings',
    ]) {
      await pumpRoute(tester, path, size: const Size(420, 900));
    }
  });
}
