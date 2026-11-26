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
import 'package:lexiloop/features/word_detail/cards/definitions_card.dart';
import 'package:lexiloop/features/word_detail/cards/note_card.dart';
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
  /// inflate，`find.byType(TextField)` 自然找不到它。页面新增了「初始化质量」
  /// 卡片后需要的高度又涨了一截。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3200);
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
    // 按钮文案写明去处：原来是「返回」，而它在 `context.go` 进入的页面上
    // 调 `maybePop()`，栈里没上一页时按下去什么都不发生。
    expect(find.widgetWithText(FilledButton, '返回单词本'), findsOneWidget);
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

    // 按 key 定位而不是按 `TextField` 类型：详情页现在有两个输入框
    // （笔记与手工释义），按类型取到哪一个取决于渲染顺序。
    final field = find.byKey(noteFieldKey);
    expect(tester.widget<TextField>(field).controller!.text, '旧笔记');
    await tester.enterText(field, '新笔记');
    await tester.ensureVisible(find.text('保存笔记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存笔记'));
    await tester.pumpAndSettle();

    final row = await (db.select(
      db.words,
    )..where((word) => word.id.equals(id))).getSingle();
    expect(row.userNote, '新笔记');
  });

  testWidgets('手工释义保存后前置到 definitions_json 首位', (tester) async {
    useTallViewport(tester);
    final id = await insertWord();

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(manualDefinitionFieldKey), '苹果树');
    await tester.ensureVisible(find.text('保存释义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存释义'));
    await tester.pumpAndSettle();

    expect(find.text('苹果树'), findsNWidgets(2));
    final row = await (db.select(
      db.wordContents,
    )..where((row) => row.wordId.equals(id))).getSingle();
    expect(row.definitionsJson, contains('苹果树'));
  });

  testWidgets('删除词条需二次确认，确认后词条与内容一并消失', (tester) async {
    useTallViewport(tester);
    final id = await insertWord();

    await tester.pumpWidget(wrap(WordDetailPage(wordId: id)));
    await tester.pumpAndSettle();

    // 删除已经收进「⋯」菜单：它此前与「重新生成」并排，两者都是不可逆操作。
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除词条'));
    await tester.pumpAndSettle();
    // 菜单项与确认对话框标题同名，此时应当只剩对话框那一处。
    expect(find.text('删除词条'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(await db.select(db.words).get(), isEmpty);
    expect(await db.select(db.wordContents).get(), isEmpty);
    expect(find.text('词条不存在或已被删除'), findsOneWidget);
  });
}
