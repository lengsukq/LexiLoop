/// 词库列表页的 widget 测试。
///
/// **为什么用测试内的最小路由表而不是 `app/router.dart`**：真实路由用
/// `StatefulShellRoute.indexedStack`，一挂上就会把 8 个分支全构建一遍，
/// 其中包含首页统计、学习会话这些与本页无关、还会自己起定时器的页面。
/// 这里只注册本页会跳转到的五个地址，断言的是「点下去落到了哪个路由」，
/// 既够用又不被别的页面的生命周期牵走。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/words/widgets/word_card.dart';
import 'package:lexiloop/features/words/widgets/word_filter_bar.dart';
import 'package:lexiloop/features/words/widgets/word_paginator.dart';
import 'package:lexiloop/features/words/widgets/words_header.dart';
import 'package:lexiloop/features/words/words_page.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  // 必须包成闭包：`tearDown(db.close)` 会在注册期就求值 `db.close`，
  // 而 `late db` 此时还没被 `setUp` 初始化，整个测试文件会在加载阶段
  // 抛 LateError（表现为 "Local 'db' has not been initialized"）。
  tearDown(() => db.close());

  /// 建一个词条，挂上可选的错词状态与复习卡。
  Future<int> insertWord({
    String term = 'word',
    InitializationStatus status = InitializationStatus.ready,
    MasteryLevel mastery = MasteryLevel.newWord,
    int score = 0,
    bool suspended = false,
    String? note,
    int? createdAt,
    int? sourceCreatedAt,
    bool wrongActive = false,
    int? dueAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: Value<InitializationStatus>(status),
            masteryLevel: Value<MasteryLevel>(mastery),
            masteryScore: Value<int>(score),
            isSuspended: Value<bool>(suspended),
            userNote: Value<String?>(note),
            sourceCreatedAt: Value<int?>(sourceCreatedAt),
            createdAt: createdAt ?? now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wrongWordStates)
        .insert(
          WrongWordStatesCompanion.insert(
            wordId: Value<int>(id),
            active: Value<bool>(wrongActive),
            updatedAt: now,
          ),
        );
    if (dueAt != null) {
      await db
          .into(db.reviewCards)
          .insert(
            ReviewCardsCompanion.insert(
              wordId: Value<int>(id),
              dueAt: dueAt,
              stability: 1,
              difficulty: 5,
              elapsedDays: 0,
              scheduledDays: 1,
              reps: 1,
              lapses: 0,
              fsrsState: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    return id;
  }

  /// 铺满两页的词条：创建时间相同，因此排序退化成 `id DESC`，
  /// 第 N 页的内容可以算出来，断言不依赖时间抖动。
  Future<void> insertTwoPages() async {
    for (var i = 0; i <= wordListPageSize; i += 1) {
      await insertWord(
        term: 'w${i.toString().padLeft(2, '0')}',
        createdAt: 1000,
      );
    }
  }

  Future<void> pumpPage(WidgetTester tester, {double width = 1400}) async {
    tester.view.physicalSize = Size(width, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: LexiTheme.light,
          routerConfig: _testRouter(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打开页面并读取当前查询条件，用于断言筛选是否真的进了状态。
  WordQuery queryOf(WidgetTester tester) {
    return ProviderScope.containerOf(tester.element(find.byType(WordsPage)))
        .read(wordQueryProvider);
  }

  group('分页', () {
    testWidgets('翻到第二页会带着偏移量重查列表', (tester) async {
      await insertTwoPages();
      await pumpPage(tester);

      expect(
        find.text('第 1 / 2 页 · 共 ${wordListPageSize + 1} 个词条'),
        findsOneWidget,
      );
      // 第一页按 id 倒序，最后插入的 w40 在最上面。
      expect(
        find.descendant(of: find.byType(WordCard), matching: find.text('w40')),
        findsOneWidget,
      );

      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      expect(
        find.text('第 2 / 2 页 · 共 ${wordListPageSize + 1} 个词条'),
        findsOneWidget,
      );
      // 第二页只剩最早的 w00：看到它就说明页码真的进了 SQL。
      expect(
        find.descendant(of: find.byType(WordCard), matching: find.text('w00')),
        findsOneWidget,
      );
      expect(queryOf(tester).offset, wordListPageSize);

      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();

      expect(
        find.text('第 1 / 2 页 · 共 ${wordListPageSize + 1} 个词条'),
        findsOneWidget,
      );
      expect(queryOf(tester).offset, 0);
    });

    testWidgets('改搜索词会回到第一页', (tester) async {
      await insertTwoPages();
      await pumpPage(tester);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'w00');
      await tester.pumpAndSettle();

      // 只命中一个词条：既钉住了页码复位，也钉住了查询确实重跑了。
      expect(find.text('第 1 / 1 页 · 共 1 个词条'), findsOneWidget);
      expect(queryOf(tester).offset, 0);
    });

    testWidgets('改筛选会回到第一页', (tester) async {
      await insertWord(term: 'alpha', mastery: MasteryLevel.mastered);
      for (var i = 0; i <= wordListPageSize; i += 1) {
        await insertWord(
          term: 'w${i.toString().padLeft(2, '0')}',
          createdAt: 1000,
        );
      }
      await pumpPage(tester);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('已掌握'),
        ),
      );
      await tester.pumpAndSettle();

      expect(queryOf(tester).offset, 0);
      expect(find.text('第 1 / 1 页 · 共 1 个词条'), findsOneWidget);
    });
  });

  group('筛选', () {
    testWidgets('错词芯片只留下活跃错词', (tester) async {
      await insertWord(term: 'wrong-one', wrongActive: true);
      await insertWord(term: 'plain-one');
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('错词'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(WordCard),
          matching: find.text('wrong-one'),
        ),
        findsOneWidget,
      );
      expect(find.text('第 1 / 1 页 · 共 1 个词条'), findsOneWidget);
    });

    testWidgets('到期芯片只留下已到期的复习卡', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(term: 'overdue', dueAt: now - dayMs);
      await insertWord(term: 'upcoming', dueAt: now + 7 * dayMs);
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('到期'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('overdue'), findsOneWidget);
      expect(find.text('upcoming'), findsNothing);
    });

    testWidgets('已暂停芯片只留下被暂停的词条', (tester) async {
      await insertWord(term: 'paused-one', suspended: true);
      await insertWord(term: 'running-one');
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('已暂停'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('paused-one'), findsOneWidget);
      expect(find.text('running-one'), findsNothing);
    });

    testWidgets('初始化状态下拉框可切换', (tester) async {
      await insertWord(term: 'ready-one');
      await insertWord(term: 'failed-one', status: InitializationStatus.failed);
      await pumpPage(tester);

      await tester.tap(find.text('全部初始化状态'));
      await tester.pumpAndSettle();
      // 展开后的菜单项挂在 overlay 路由里，不是 DropdownButton 的后代；
      // 卡片上的状态徽标也叫「失败」，因此取最后一个（overlay 后插入）。
      await tester.tap(find.text('失败').last);
      await tester.pumpAndSettle();

      expect(find.text('failed-one'), findsOneWidget);
      expect(find.text('ready-one'), findsNothing);
    });

    testWidgets('三个特殊筛选互相独立，可叠加', (tester) async {
      await insertWord(term: 'both', wrongActive: true, suspended: true);
      await insertWord(term: 'only-wrong', wrongActive: true);
      await insertWord(term: 'only-suspended', suspended: true);
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('错词'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(WordFilterBar),
          matching: find.text('已暂停'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('both'), findsOneWidget);
      expect(find.text('only-wrong'), findsNothing);
      expect(find.text('only-suspended'), findsNothing);
    });
  });

  group('排序', () {
    testWidgets('下拉框切换到「来源时间」后按它排序', (tester) async {
      await insertWord(
        term: 'old-source',
        sourceCreatedAt: 1000,
        createdAt: 9000,
      );
      await insertWord(
        term: 'new-source',
        sourceCreatedAt: 8000,
        createdAt: 1000,
      );
      await pumpPage(tester);

      await tester.tap(find.text('创建时间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('来源时间').last);
      await tester.pumpAndSettle();

      expect(queryOf(tester).sort.label, '来源时间');
      final cards = _cardTerms(tester);
      expect(cards.first, 'new-source');
    });

    testWidgets('下拉框切换到「到期时间」后没有卡片的词条排在最后', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(term: 'no-card');
      await insertWord(term: 'later-due', dueAt: now + 3 * dayMs);
      await insertWord(term: 'sooner-due', dueAt: now + dayMs);
      await pumpPage(tester);

      await tester.tap(find.text('创建时间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('到期时间').last);
      await tester.pumpAndSettle();

      expect(_cardTerms(tester), <String>[
        'later-due',
        'sooner-due',
        'no-card',
      ]);
    });
  });

  group('搜索', () {
    testWidgets('关键词能命中词条与备注', (tester) async {
      await insertWord(term: 'apple');
      await insertWord(term: 'banana', note: '和 apple 很像');
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pumpAndSettle();

      // 断言必须落在卡片上：搜索框自己也含 'apple'，
      // 直接 find.text 会把输入框一起数进来。
      // 顺序是默认排序（创建时间倒序）：banana 后插入，因此排在前面。
      expect(_cardTerms(tester), <String>['banana', 'apple']);

      await tester.enterText(find.byType(TextField), '很像');
      await tester.pumpAndSettle();

      expect(_cardTerms(tester), <String>['banana']);
    });

    testWidgets('「清除搜索」清空输入框并回到第一页', (tester) async {
      await insertTwoPages();
      await pumpPage(tester);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'w01');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
      );
      expect(queryOf(tester).search, '');
      expect(
        find.text('第 1 / 2 页 · 共 ${wordListPageSize + 1} 个词条'),
        findsOneWidget,
      );
    });
  });

  group('卡片', () {
    testWidgets('错词 / 已暂停 / 到期 徽标按数据出现', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(
        term: 'flagged',
        wrongActive: true,
        suspended: true,
        dueAt: now - dayMs,
      );
      await insertWord(term: 'plain');
      await pumpPage(tester);

      final flagged = find.ancestor(
        of: find.text('flagged'),
        matching: find.byType(WordCard),
      );
      final plain = find.ancestor(
        of: find.text('plain'),
        matching: find.byType(WordCard),
      );

      expect(
        find.descendant(of: flagged, matching: find.text('错词')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flagged, matching: find.text('已暂停')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flagged, matching: find.text('到期')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plain, matching: find.text('错词')),
        findsNothing,
      );
      expect(
        find.descendant(of: plain, matching: find.text('已暂停')),
        findsNothing,
      );
      expect(
        find.descendant(of: plain, matching: find.text('到期')),
        findsNothing,
      );
    });

    testWidgets('卡片显示语向与到期日', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = DateTime.fromMillisecondsSinceEpoch(now + dayMs);
      await insertWord(term: 'directed', dueAt: now + dayMs);
      await pumpPage(tester);

      final card = find.ancestor(
        of: find.text('directed'),
        matching: find.byType(WordCard),
      );

      expect(
        find.descendant(of: card, matching: find.text('en → zh')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('${due.month} 月 ${due.day} 日'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('朗读按钮存在且可点（音频层尚未接线）', (tester) async {
      await insertWord(term: 'speakable');
      await pumpPage(tester);

      final button = find.descendant(
        of: find.byType(WordCard),
        matching: find.byTooltip('朗读发音'),
      );
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      // 占位实现：不崩、不跳转，卡片仍在原处。
      expect(find.text('speakable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('头部入口', () {
    testWidgets('「手动添加」跳到 /add', (tester) async {
      await insertWord(term: 'alpha');
      await pumpPage(tester);

      await tester.tap(find.text('手动添加'));
      await tester.pumpAndSettle();

      expect(find.text('标记：/add'), findsOneWidget);
    });

    testWidgets('「CSV 导入」跳到 /import', (tester) async {
      await insertWord(term: 'alpha');
      await pumpPage(tester);

      await tester.tap(find.text('CSV 导入'));
      await tester.pumpAndSettle();

      expect(find.text('标记：/import'), findsOneWidget);
    });

    testWidgets('头部显示当前筛选下的词条数', (tester) async {
      await insertWord(term: 'alpha');
      await insertWord(term: 'beta');
      await pumpPage(tester);

      expect(
        find.descendant(
          of: find.byType(WordsHeader),
          matching: find.text('共 2 个词条'),
        ),
        findsOneWidget,
      );
    });
  });

  group('掌握概览', () {
    testWidgets('显示已掌握数、剩余数与百分比', (tester) async {
      await insertWord(term: 'a', mastery: MasteryLevel.mastered);
      await insertWord(term: 'b', mastery: MasteryLevel.mastered);
      await insertWord(term: 'c');
      await insertWord(term: 'd');
      await pumpPage(tester);

      expect(find.text('已掌握 2 / 4 个词条 · 还有 2 个待继续学习'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('「详细统计」跳到 /statistics', (tester) async {
      await insertWord(term: 'a', mastery: MasteryLevel.mastered);
      await pumpPage(tester);

      await tester.tap(find.text('详细统计'));
      await tester.pumpAndSettle();

      expect(find.text('标记：/statistics'), findsOneWidget);
    });

    testWidgets('库里没有词条时不显示概览', (tester) async {
      await pumpPage(tester);

      expect(find.text('当前词条掌握程度'), findsNothing);
    });
  });

  group('空状态', () {
    testWidgets('没有词条时同时给出两个导入入口', (tester) async {
      await pumpPage(tester);

      expect(find.text('还没有词条'), findsOneWidget);
      // 头部与空状态各有一个「导入备份」，「CSV 导入」也在两处。
      expect(find.text('导入备份'), findsNWidgets(2));
      expect(find.text('CSV 导入'), findsNWidgets(2));

      // 头部与空状态各有一个「CSV 导入」，这里点空状态里的那个。
      await tester.tap(find.text('CSV 导入').last);
      await tester.pumpAndSettle();

      expect(find.text('标记：/import'), findsOneWidget);
    });

    testWidgets('被筛空时只提示调整筛选，不给导入入口', (tester) async {
      await insertWord(term: 'alpha');
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('没有匹配的词条'), findsOneWidget);
      expect(find.text('调整筛选条件或清空搜索词后再试。'), findsOneWidget);
      // 空状态里的两个导入入口消失了，只剩头部那个。
      expect(find.text('CSV 导入'), findsOneWidget);
    });

    testWidgets('结果为空时不显示分页条', (tester) async {
      await pumpPage(tester);

      expect(find.byType(WordPaginator), findsOneWidget);
      expect(find.textContaining('第 1 / 1 页'), findsNothing);
    });
  });

  group('窄屏筛选面板', () {
    testWidgets('筛选按钮带生效中的筛选数', (tester) async {
      await insertWord(term: 'alpha', wrongActive: true);
      await insertWord(term: 'paused', suspended: true);
      await pumpPage(tester, width: 800);

      expect(find.text('筛选'), findsOneWidget);

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      // 必须限定在弹层里：卡片上的状态徽标也叫「错词」「已暂停」，
      // 不限定就会命中多个目标而无法点击。
      await tester.tap(_inSheet('错词'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('已暂停'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('完成'));
      await tester.pumpAndSettle();

      expect(find.text('筛选 2'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
    });

    testWidgets('「清除筛选」清掉全部筛选并回到第一页', (tester) async {
      await insertTwoPages();
      await pumpPage(tester, width: 800);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('错词'));
      await tester.pumpAndSettle();
      await tester.tap(_inSheet('清除筛选'));
      await tester.pumpAndSettle();

      final query = queryOf(tester);
      expect(query.activeFilterCount, 0);
      expect(query.offset, 0);
      expect(find.text('筛选'), findsOneWidget);
    });
  });
}

/// 本组用例专用路由表：只注册本页会跳转到的地址。
GoRouter _testRouter() => GoRouter(
  initialLocation: '/words',
  routes: <RouteBase>[
    GoRoute(path: '/words', builder: (_, _) => const WordsPage()),
    GoRoute(
      path: '$wordDetailPathPrefix:id',
      builder: (_, _) => const _RouteMarker('/words/:id'),
    ),
    GoRoute(
      path: addWordPath,
      builder: (_, _) => const _RouteMarker(addWordPath),
    ),
    GoRoute(
      path: csvImportPath,
      builder: (_, _) => const _RouteMarker(csvImportPath),
    ),
    GoRoute(
      path: statisticsPath,
      builder: (_, _) => const _RouteMarker(statisticsPath),
    ),
  ],
);

/// 落点标记：把当前路由路径显示在屏幕上供断言。
class _RouteMarker extends StatelessWidget {
  const new(this.location);

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('标记：$location')));
  }
}

/// 屏幕上卡片词形的上下顺序，用于断言排序。
List<String> _cardTerms(WidgetTester tester) {
  return tester
      .widgetList<WordCard>(find.byType(WordCard))
      .map((card) => card.entry.term)
      .toList();
}

/// 窄屏筛选弹层里的某个控件。
///
/// 弹层与卡片会显示同一个词（「错词」「已暂停」既是筛选名也是状态徽标），
/// 不限定范围就会命中多个目标。
Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
