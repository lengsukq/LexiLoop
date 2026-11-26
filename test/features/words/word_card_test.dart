/// 词库列表卡片上两个就地操作的 widget 测试。
///
/// 朗读按钮曾经是空实现（`void _speak() {}`），这一组测试钉住它真的走
/// `WordSpeaker`、并且带上了列表查询取回的发音数据；编辑入口打开的是与
/// 详情页同一个弹窗。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/words/widgets/word_card.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

import '../../support/app_harness.dart';
import '../word_detail/word_write_test_support.dart';

void main() {
  late AppDatabase db;
  late RecordingSpeaker speaker;
  late FakeWordLookup lookup;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    speaker = RecordingSpeaker();
    lookup = FakeWordLookup();
  });

  tearDown(() async {
    await db.close();
  });

  /// 取列表查询返回的第一行。
  Future<WordListEntry> entryOf(int wordId) async {
    final entries = await WordDao(db).list(const WordQuery());
    return entries.firstWhere((entry) => entry.id == wordId);
  }

  /// 渲染一张卡片。
  Future<void> pumpCard(WidgetTester tester, WordListEntry entry) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithScope(
        WordCard(entry: entry, onTap: () {}),
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          wordSpeakerProvider.overrideWithValue(speaker),
          wordContentRefreshServiceProvider.overrideWithValue(
            WordContentRefreshService(
              db,
              SettingsService(SettingsDao(db)),
              lookup,
              WordEditService(db),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列表查询带回发音数据', (tester) async {
    final id = await insertWordRow(
      db,
      pronunciationsJson:
          '[{"accent":"UK","phonetic":"ˈæpl","audioUrl":"https://x/a.mp3"}]',
    );

    final entry = await entryOf(id);

    expect(entry.pronunciations, hasLength(1));
    expect(entry.pronunciations.single.phonetic, 'ˈæpl');
    expect(entry.pronunciations.single.audioUrl, 'https://x/a.mp3');
  });

  testWidgets('点朗读按钮走 WordSpeaker 并带上发音数据', (tester) async {
    final id = await insertWordRow(
      db,
      pronunciationsJson:
          '[{"accent":"US","phonetic":"ˈæpl","source":"youdao"}]',
    );
    await pumpCard(tester, await entryOf(id));

    await tester.tap(find.byTooltip('朗读发音'));
    await tester.pumpAndSettle();

    expect(speaker.requests, hasLength(1));
    expect(speaker.requests.single.term, 'apple');
    expect(speaker.requests.single.pronunciations, hasLength(1));
  });

  testWidgets('点编辑按钮打开编辑词条弹窗', (tester) async {
    final id = await insertWordRow(db);
    await pumpCard(tester, await entryOf(id));

    await tester.tap(find.byTooltip('词条操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑词条'));
    await tester.pumpAndSettle();

    expect(find.text('编辑词条'), findsOneWidget);
    expect(find.text('词条文本'), findsOneWidget);
  });
}
