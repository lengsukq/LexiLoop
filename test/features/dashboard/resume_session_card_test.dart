/// 「继续上次学习」卡片的 Widget 测试。
///
/// 对应旧版 `src/app/(main)/page.tsx:142-148`。这里钉三件事，而不是截图：
/// 1. **副标题用的是展示用的会话类型**——旧版 `statistics/service.ts` 对
///    `AI_RECOMMENDED` / `SENTENCE_REVIEW` 取 `source_type`，其余取
///    `session_type`，标签取错了用户就不知道点进去会做什么；
/// 2. **落点是 `/study?mode=<wire>`**，且与标签是同一个模式；
/// 3. **没有会话、以及会话还没查出来时都不渲染**——空卡片与「加载中先渲染
///    再撤掉」都会把用户引到一个无事可做的入口上。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/resume_session_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late int now;

  /// 学习页实际落到的地址（含 query），供断言深链。
  String? landedLocation;

  setUp(() {
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    landedLocation = null;
  });

  /// 造一条可恢复会话；[mode] 是**展示用**的会话类型。
  ResumableSession sessionOf(StudyMode mode, {int remainingCount = 3}) =>
      ResumableSession(
        id: 7,
        mode: mode,
        remainingCount: remainingCount,
        plannedCount: 10,
        startedAt: now,
      );

  /// 挂上最小路由表并渲染卡片。
  ///
  /// [load] 决定 provider 返回什么（`null`、一条会话，或一个永不完成的
  /// Future 用来模拟加载中）；[settle] 为 false 时只 `pump` 一帧——
  /// 对永不完成的 Future 调 `pumpAndSettle` 会直接超时。
  Future<void> showCard(
    WidgetTester tester, {
    required Future<ResumableSession?> Function() load,
    bool settle = true,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(child: ResumeSessionCard()),
          ),
        ),
        GoRoute(
          path: '/study',
          builder: (context, state) {
            landedLocation = state.uri.toString();
            return const Scaffold(body: Center(child: Text('学习页')));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          resumableSessionProvider.overrideWith((ref) => load()),
        ],
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('有可恢复会话时显示类型标签与剩余题数', (tester) async {
    await showCard(tester, load: () async => sessionOf(StudyMode.wrongWords));

    expect(find.byKey(resumeSessionCardKey), findsOneWidget);
    expect(find.text('继续上次学习'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(resumeSessionSubtitleKey)).data,
      '错词强化 · 还剩 3 题',
    );
  });

  testWidgets('点击「继续」跳到该模式的 /study?mode=...', (tester) async {
    await showCard(tester, load: () async => sessionOf(StudyMode.wrongWords));

    await tester.tap(find.byKey(resumeSessionContinueKey));
    await tester.pumpAndSettle();

    expect(landedLocation, '/study?mode=WRONG_WORDS');
    expect(find.text('学习页'), findsOneWidget);
  });

  testWidgets('标签与落点都跟着展示用的会话类型走（AI 推荐）', (tester) async {
    await showCard(
      tester,
      load: () async => sessionOf(StudyMode.aiRecommended, remainingCount: 2),
    );

    expect(
      tester.widget<Text>(find.byKey(resumeSessionSubtitleKey)).data,
      'AI 推荐 · 还剩 2 题',
    );

    await tester.tap(find.byKey(resumeSessionContinueKey));
    await tester.pumpAndSettle();

    expect(landedLocation, '/study?mode=AI_RECOMMENDED');
  });

  testWidgets('没有可恢复会话时整张卡片不渲染', (tester) async {
    await showCard(tester, load: () async => null);

    expect(find.byKey(resumeSessionCardKey), findsNothing);
    expect(find.byKey(resumeSessionSubtitleKey), findsNothing);
    expect(find.text('继续上次学习'), findsNothing);
  });

  testWidgets('会话尚未查出来时不渲染空卡片', (tester) async {
    await showCard(
      tester,
      load: () => Completer<ResumableSession?>().future,
      settle: false,
    );

    expect(find.byKey(resumeSessionCardKey), findsNothing);
    expect(find.text('继续上次学习'), findsNothing);
  });
}
