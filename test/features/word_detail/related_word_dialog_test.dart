/// 关联词弹窗的 widget 测试。
///
/// 钉住旧版的按钮分流：库里没有该词时是「加入词库并初始化」，已有但内容
/// 不全时是「加入初始化」，已经就绪时干脆不给按钮。这三条决定用户会不会
/// 反复点一个永远没反应的按钮。
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/dialogs/related_word_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/services/related_word_service.dart';

import '../../support/app_harness.dart';
import 'word_write_test_support.dart';

/// 可以卡住预览查询的假关联词服务。
///
/// 用来确定性地观察「正在检查词库状态…」：真服务的查询在内存库上快得
/// 看不见，靠时序去撞加载态必然是 flaky 的。
class GatedRelatedWordService extends RelatedWordService {
  /// 以数据库与闸门构造。
  new(super._db, this.gate);

  /// 放行预览查询的闸门。
  final Completer<void> gate;

  @override
  Future<RelatedWordPreview> preview({
    required int parentWordId,
    required String rawTerm,
  }) async {
    await gate.future;
    return await super.preview(parentWordId: parentWordId, rawTerm: rawTerm);
  }
}

void main() {
  late AppDatabase db;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入父词条（带一条易混词说明）。
  Future<int> insertParent() => insertWordRow(
    db,
    confusedWordsJson:
        '[{"word":"apply","relation":"CONFUSED_WITH",'
        '"translation":"申请","partOfSpeech":"v.",'
        '"difference":"apply 强调申请。","source":"ai"}]',
    now: now,
  );

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 打开关联词弹窗。
  Future<void> open(
    WidgetTester tester, {
    required int parentWordId,
    String term = 'apply',
    RelationType relation = RelationType.confusedWith,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RelatedWordDialog.show(
              context,
              parentWordId: parentWordId,
              term: term,
              relation: relation,
            ),
            child: const Text('打开'),
          ),
        ),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.tap(find.text('打开'));
  }

  Future<List<WordRow>> allWords() => db.select(db.words).get();

  Future<List<InitializationJobRow>> jobs() =>
      db.select(db.initializationJobs).get();

  testWidgets('检查中显示提示，随后显示关系徽标、译文与区别说明', (tester) async {
    final parentId = await insertParent();
    final gate = Completer<void>();
    useTallViewport(tester);
    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => RelatedWordDialog.show(
              context,
              parentWordId: parentId,
              term: 'apply',
              relation: RelationType.confusedWith,
            ),
            child: const Text('打开'),
          ),
        ),
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          relatedWordServiceProvider.overrideWithValue(
            GatedRelatedWordService(db, gate),
          ),
        ],
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    expect(find.text('正在检查词库状态…'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('易混词'), findsOneWidget);
    expect(find.text('apply'), findsOneWidget);
    expect(find.text('申请'), findsOneWidget);
    expect(find.text('apply 强调申请。'), findsOneWidget);
    expect(find.text('词库状态'), findsOneWidget);
    expect(find.text('尚未加入'), findsOneWidget);
    expect(find.text('语言方向'), findsOneWidget);
    expect(find.text('英语 → 中文'), findsOneWidget);
    expect(find.text('词性'), findsOneWidget);
    expect(find.text('v.'), findsOneWidget);
  });

  testWidgets('尚未加入时按钮为「加入词库并初始化」，点击后建词条并入队', (tester) async {
    final parentId = await insertParent();

    await open(tester, parentWordId: parentId);
    await tester.pumpAndSettle();

    expect(find.text('打开词条'), findsNothing);
    await tester.tap(find.text('加入词库并初始化'));
    await tester.pumpAndSettle();

    expect(find.text('已加入词库并排入初始化队列。'), findsOneWidget);
    final words = await allWords();
    expect(words, hasLength(2));
    final created = words.firstWhere((row) => row.term == 'apply');
    expect(created.initializationStatus, InitializationStatus.queued);
    expect(await jobs(), hasLength(1));
    expect(find.text('加入词库并初始化'), findsNothing, reason: '加入之后按钮应消失，避免用户连点');
    expect(find.text('打开词条'), findsOneWidget);
  });

  testWidgets('已在库但内容不全时按钮为「加入初始化」且不建重复词条', (tester) async {
    final parentId = await insertParent();
    final existingId = await insertWordRow(db, term: 'apply', now: now);

    await open(tester, parentWordId: parentId);
    await tester.pumpAndSettle();

    expect(find.text('待初始化'), findsOneWidget);
    expect(find.text('打开词条'), findsOneWidget);
    await tester.tap(find.text('加入初始化'));
    await tester.pumpAndSettle();

    expect(find.text('已排入初始化队列。'), findsOneWidget);
    expect(await allWords(), hasLength(2));
    final queued = await jobs();
    expect(queued, hasLength(1));
    expect(queued.single.wordId, existingId);
  });

  testWidgets('内容已就绪时不给加入按钮', (tester) async {
    final parentId = await insertParent();
    await insertWordRow(
      db,
      term: 'apply',
      status: InitializationStatus.ready,
      now: now,
    );

    await open(tester, parentWordId: parentId);
    await tester.pumpAndSettle();

    expect(find.text('已就绪'), findsOneWidget);
    expect(find.text('打开词条'), findsOneWidget);
    expect(find.text('加入初始化'), findsNothing);
    expect(find.text('加入词库并初始化'), findsNothing);
  });

  testWidgets('与父词条相同时报错', (tester) async {
    final parentId = await insertParent();

    await open(tester, parentWordId: parentId, term: 'Apple');
    await tester.pumpAndSettle();

    expect(find.text('不能把当前词条再次加入词库。'), findsOneWidget);
    expect(find.text('加入词库并初始化'), findsNothing);
  });
}
