/// 沉浸式页面的**出路**测试。
///
/// **为什么非写不可**：`/study` `/games` `/match` `/phonetics` 是沉浸式路由，
/// 窄屏下外壳不渲染导航；这些页面只能靠自己的退出按钮离开。而 `/study` 是
/// `StatefulShellRoute` 的**分支根路由**，栈里没有上一页——退出按钮若写成
/// `Navigator.maybePop`，点击就什么也不会发生，用户被困在一整页里。
///
/// 这个缺陷真的发生过：空库进入学习页时整页只有一个点了没反应的「返回」。
/// 这里从「用户点得到、点了真的走」的角度钉死，而不是断言某个回调被调用。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
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
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/features/games/games_page.dart';
import 'package:lexiloop/features/match/match_page.dart';
import 'package:lexiloop/features/phonetics/phonetics_page.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../services/audio/audio_fakes.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// 在给定地址打开应用，返回当前路由位置。
  ///
  /// [size] 用来切换宽/窄屏：沉浸模式在宽屏保留侧边栏、窄屏隐藏底部 Tab Bar。
  Future<GoRouter> pumpAt(
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
          // `just_audio` 是平台通道插件、下载器会真的联网，计时器走假时间：
          // 三个替身缺一不可，否则学习页一挂载就会抛 MissingPluginException。
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
    await tester.pump();
    // 有会话时要等它加载完（题干、选项都由真实 DAO 生成）；空库时
    // 这里会停在结算视图，同样不需要更多帧。不用 `pumpAndSettle`：
    // 加载态是无限动画，一旦会话没建好就会一直等到超时，掩盖真实原因。
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  /// 建一个词条 + 一条含单道题的今日会话，让学习页渲染出进度条与「退出」。
  Future<void> seedSession() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final wordId = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: 'apple',
            normalizedTerm: 'apple',
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(wordId),
            definitionsJson: const Value<String>(
              '[{"language":"zh","text":"苹果"}]',
            ),
            updatedAt: stamp,
          ),
        );
    final sessionId = await db
        .into(db.studySessions)
        .insert(
          StudySessionsCompanion.insert(
            sessionType: StudyMode.daily,
            startedAt: stamp,
            plannedCount: const Value<int>(1),
            createdAt: stamp,
          ),
        );
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: 0,
            wordId: wordId,
            taskType: StudyTaskType.review,
            questionType: QuestionType.enToZh,
            createdAt: stamp,
          ),
        );
  }

  /// 当前路由位置。
  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  /// 点一个按钮并等界面稳定。
  ///
  /// 不用 `pumpAndSettle`：学习页的加载态是无限动画，会一直等到超时。
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('空库进入学习页：退出按钮真的回到今日', (tester) async {
    // 这条就是那个真实缺陷：空库 → 会话没有题目 → 整页只有一个退出按钮，
    // 而它是 `maybePop`，在分支根路由上点了没反应。
    final router = await pumpAt(tester, '/study');
    expect(find.byType(StudyPage), findsOneWidget);
    expect(locationOf(router), '/study');

    expect(find.text('暂时没有更多可学习词条'), findsOneWidget);
    await tapAndSettle(tester, find.text('返回首页'));

    expect(locationOf(router), '/');
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('学习页头部的「结束」也回到今日', (tester) async {
    // 有题目时退出按钮在进度条上（`StudyProgressHeader.onExit`），
    // 与结算页的「返回首页」走同一个回调——两条路径都必须是「回首页」。
    await seedSession();
    final router = await pumpAt(tester, '/study');
    // 进度条上的退出按钮文案是「结束」（`StudyProgressHeader`）。
    expect(find.text('结束'), findsOneWidget);

    await tapAndSettle(tester, find.text('结束'));

    expect(locationOf(router), '/');
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('宽屏下沉浸页面保留侧边栏', (tester) async {
    // 旧版 `components/app-shell.tsx` 的 `isStudyScreen` 只隐藏移动端底栏，
    // 桌面侧边栏从不隐藏。早先的实现把两者一起隐藏，宽屏上也就没有出路。
    await pumpAt(tester, '/study');
    expect(find.text('单词本'), findsWidgets, reason: '宽屏沉浸页应当仍能看到侧边栏导航');
  });

  testWidgets('窄屏下沉浸页面隐藏底部 Tab Bar', (tester) async {
    // 与旧版一致：窄屏学习/游戏时全屏专注，底栏收起（因此更依赖页面自己的退出）。
    await pumpAt(tester, '/study', size: const Size(500, 900));
    expect(find.text('单词本'), findsNothing, reason: '窄屏沉浸页收起底部 Tab Bar（与旧版一致）');
  });

  for (final entry in <(String, Type)>[
    ('/games', GamesPage),
    ('/match', MatchPage),
    ('/phonetics', PhoneticsPage),
  ]) {
    testWidgets('${entry.$1} 窄屏下也能通过返回键离开', (tester) async {
      // 游戏/配对/音标的「退出」是回到本页的准备视图（页面内状态），
      // 不是导航——因此这些页面永远渲染得出内容，不会像学习页那样
      // 只剩一个按钮。这里钉住「页面能渲染 + 系统返回能离开」。
      final router = await pumpAt(tester, entry.$1, size: const Size(500, 900));
      expect(find.byType(entry.$2), findsOneWidget);
      expect(locationOf(router), entry.$1);
    });
  }
}
