/// 顶层路由的准备页必须能离开这一页。
///
/// `/match` 与 `/phonetics` 都是沉浸式顶层路由：不套 `AdaptiveShell`，
/// 没有侧边栏也没有底部 Tab。而两个准备页此前的唯一「退出」入口是
/// `exit()`——它只是把状态退回准备态，也就是用户已经站着的地方。
/// 桌面端因此没有任何可见出口，只能靠系统手势。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../services/audio/audio_fakes.dart';

void main() {
  Future<GoRouter> pumpRoute(WidgetTester tester, String route) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = createAppRouter(initialLocation: route);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          audioPlayerPortProvider.overrideWithValue(FakeAudioPlayer()),
          audioDownloaderProvider.overrideWithValue(FakeAudioDownloader()),
          studyClockFactoryProvider.overrideWithValue(
            () => StudyClock(
              now: () => DateTime(2026, 3, 1, 10).millisecondsSinceEpoch,
            ),
          ),
        ],
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final route in <String>[matchPath, phoneticsPath]) {
    testWidgets('$route 的准备页有返回入口，点了回到训练页', (tester) async {
      final router = await pumpRoute(tester, route);

      expect(find.byKey(const Key('pageHeaderBack')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pageHeaderBack')));
      await tester.pumpAndSettle();

      // 兜底落点是训练页：这两个页面都是从那里进来的。
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        gamesPath,
        reason: '返回后应当落在 $gamesPath',
      );
    });
  }
}
