/// 词条详情页的 Widget 测试。
///
/// 覆盖三件事：真实数据能渲染、词条不存在时给出空态、写操作真的落库。
/// 后两条是旧版详情页最容易「看起来正常但实际没生效」的地方——
/// 删除按钮没接级联、暂停开关只改了本地状态。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/word_detail_page.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

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

  /// 用内存库替换全局数据库提供者，并套上 LexiLoop 主题。
  Widget wrap(Widget child) => ProviderScope(
    overrides: <Override>[databaseProvider.overrideWithValue(db)],
    child: MaterialApp(theme: LexiTheme.light, home: child),
  );

  /// 把测试画布调高，让整页卡片都被真实构建。
  ///
  /// `ListView` 只构建可见项，默认 800x600 的画布下「笔记」卡片不会被
  /// inflate，`find.byType(TextField)` 自然找不到它。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 插入一条带释义的词条。
  Future<int> insertWord({
    String term = 'apple',
    String definitionsJson = '[{"language":"zh","text":"苹果"}]',
    String? userNote,
    bool isSuspended = false,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            isSuspended: Value<bool>(isSuspended),
            userNote: Value<String?>(userNote),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(definitionsJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  testWidgets('渲染词条文本与释义', (tester) async {
    useTallViewport(tester);
    final id = await insertWord();

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(find.text('苹果'), findsOneWidget);
    expect(find.text('释义'), findsOneWidget);
  });

  testWidgets('词条不存在时显示空态与返回按钮', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap(const WordDetailPage(wordId: 9999)));
    await tester.pumpAndSettle();

    expect(find.text('词条不存在或已被删除'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '返回'), findsOneWidget);
  });

  testWidgets('暂停开关切换后 words.is_suspended 真的变了', (tester) async {
    useTallViewport(tester);
    final id = await insertWord();

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final row = await (db.select(
      db.words,
    )..where((word) => word.id.equals(id))).getSingle();
    expect(row.isSuspended, isTrue);
  });

  testWidgets('笔记可以编辑并保存到 words.user_note', (tester) async {
    useTallViewport(tester);
    final id = await insertWord(userNote: '旧笔记');

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '旧笔记',
    );
    await tester.enterText(find.byType(TextField), '新笔记');
    await tester.ensureVisible(find.text('保存笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存笔记'));
    await tester.pumpAndSettle();

    final row = await (db.select(
      db.words,
    )..where((word) => word.id.equals(id))).getSingle();
    expect(row.userNote, '新笔记');
  });

  testWidgets('删除词条需二次确认，确认后词条与内容一并消失', (tester) async {
    useTallViewport(tester);
    final id = await insertWord();

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('删除词条'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(await db.select(db.words).get(), isEmpty);
    expect(await db.select(db.wordContents).get(), isEmpty);
    expect(find.text('词条不存在或已被删除'), findsOneWidget);
  });
}
