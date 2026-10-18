/// 相关词条卡片可点性的 widget 测试。
///
/// 卡片曾经是只读列表：用户看得到同义词，却没有任何办法把它加进词库。
/// 这一组测试钉住「每一行都能点开加入弹窗，且带上正确的关系类型」。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/cards/related_words_card.dart';
import 'package:lexiloop/features/word_detail/word_detail_page.dart';

import '../../support/app_harness.dart';
import 'word_write_test_support.dart';

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

  /// 取父词条里的一类关联词。
  Future<List<RelatedWordView>> itemsOf(int wordId, String field) async {
    final detail = await WordDetailDao(db).find(wordId);
    return switch (field) {
      'synonyms' => detail!.synonyms,
      'antonyms' => detail!.antonyms,
      _ => detail!.confusedWords,
    };
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required int wordId,
    required RelationType relation,
    required List<RelatedWordView> items,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithScope(
        Scaffold(
          body: RelatedWordsCard(
            wordId: wordId,
            relation: relation,
            items: items,
          ),
        ),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.pumpAndSettle();
  }

  test('卡片标题与图标由关系推导', () {
    expect(relatedCardLook(RelationType.synonym).title, '同义词');
    expect(relatedCardLook(RelationType.antonym).title, '反义词');
    expect(relatedCardLook(RelationType.wordFamily).title, '词族');
    expect(relatedCardLook(RelationType.confusedWith).title, '易混词');
  });

  testWidgets('点一行打开加入弹窗并带上关系与词形', (tester) async {
    final wordId = await insertWordRow(
      db,
      confusedWordsJson:
          '[{"word":"apply","relation":"CONFUSED_WITH",'
          '"translation":"申请","difference":"apply 强调申请。"}]',
      now: now,
    );
    final items = await itemsOf(wordId, 'confusedWords');

    await pumpCard(
      tester,
      wordId: wordId,
      relation: RelationType.confusedWith,
      items: items,
    );
    expect(find.text('易混词'), findsOneWidget);
    expect(find.text('apply'), findsOneWidget);
    expect(find.text('区别：apply 强调申请。'), findsOneWidget);

    await tester.tap(find.text('apply'));
    await tester.pumpAndSettle();

    // 弹窗标题里的关系徽标用的是另一套文案（与旧版一致）。
    expect(find.text('易混词'), findsWidgets);
    expect(find.text('词库状态'), findsOneWidget);
    expect(find.text('加入词库并内容补全'), findsOneWidget);
  });

  testWidgets('四类关联词合成一张卡，一次只展开一类', (tester) async {
    final wordId = await insertWordRow(
      db,
      synonymsJson: '[{"word":"fruit","translation":"水果"}]',
      confusedWordsJson: '[{"word":"animal","translation":"动物"}]',
      now: now,
    );
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithScope(
        WordDetailPage(wordId: wordId),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('扩展知识与助记'));
    await tester.tap(find.text('扩展知识与助记'));
    await tester.pumpAndSettle();

    // 一张卡、一个切换条，而不是两张各带标题的卡。
    expect(find.text('相关词'), findsOneWidget);
    expect(find.text('同义词 1'), findsOneWidget);
    expect(find.text('易混词 1'), findsOneWidget);
    // 默认展开第一类。
    expect(find.text('fruit'), findsOneWidget);
    expect(find.text('animal'), findsNothing);

    await tester.tap(find.text('易混词 1'));
    await tester.pumpAndSettle();
    expect(find.text('animal'), findsOneWidget);
    expect(find.text('fruit'), findsNothing);
  });

  testWidgets('详情页把同义词卡片接到「近义词」关系上', (tester) async {
    final wordId = await insertWordRow(
      db,
      synonymsJson: '[{"word":"fruit","translation":"水果"}]',
      now: now,
    );
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithScope(
        WordDetailPage(wordId: wordId),
        overrides: <Override>[databaseProvider.overrideWithValue(db)],
      ),
    );
    await tester.pumpAndSettle();

    if (find.text('扩展知识与助记').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('扩展知识与助记'));
      await tester.tap(find.text('扩展知识与助记'));
      await tester.pumpAndSettle();
    }
    expect(find.text('同义词'), findsOneWidget);
    await tester.tap(find.text('fruit'));
    await tester.pumpAndSettle();

    expect(find.text('近义词'), findsOneWidget);
    expect(find.text('加入词库并内容补全'), findsOneWidget);
  });

  testWidgets('同义词卡片用近义词关系打开弹窗', (tester) async {
    final wordId = await insertWordRow(db, now: now);
    await pumpCard(
      tester,
      wordId: wordId,
      relation: RelationType.synonym,
      items: const <RelatedWordView>[
        RelatedWordView(word: 'fruit', translation: '水果'),
      ],
    );

    await tester.tap(find.text('fruit'));
    await tester.pumpAndSettle();

    expect(find.text('近义词'), findsOneWidget);
  });
}
