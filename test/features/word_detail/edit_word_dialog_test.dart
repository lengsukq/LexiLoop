/// 编辑词条弹窗的 widget 测试。
///
/// 钉住旧版的两条关键交互：改文本后用**新文本**重新抓取；只有拿到内容并
/// 确认应用，词条文本才会真正变化。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/dialogs/edit_word_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

import '../../support/app_harness.dart';
import 'word_write_test_support.dart';

void main() {
  late AppDatabase db;
  late FakeWordLookup lookup;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    lookup = FakeWordLookup();
  });

  tearDown(() async {
    await db.close();
  });

  /// 一份有道抓取结果。
  DictionaryLookupResult youdaoResult(String text) => DictionaryLookupResult(
    content: DictionaryContent(<String, Object?>{
      'definitions': <Object?>[
        <String, Object?>{'language': 'zh', 'text': text},
      ],
      'examples': <Object?>[
        <String, Object?>{'sentence': 'An example.'},
      ],
    }),
    attempts: const <ProviderAttemptRecord>[
      ProviderAttemptRecord(
        providerId: 'youdao',
        status: ProviderAttemptStatus.success,
        durationMs: 20,
        fieldsReturned: <String>['definitions'],
      ),
    ],
    hasTransientFailure: false,
    contentSource: ContentSource.dictionaryOnly,
  );

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 打开编辑弹窗的宿主页面。
  Future<void> open(
    WidgetTester tester, {
    required int wordId,
    String term = 'apple',
    VoidCallback? onSaved,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrapWithScope(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => EditWordDialog.show(
              context,
              target: EditWordTarget(
                wordId: wordId,
                term: term,
                sourceLanguage: 'en',
                targetLanguage: 'zh',
                contentType: LexicalContentType.word,
              ),
              onSaved: onSaved,
            ),
            child: const Text('打开'),
          ),
        ),
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
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
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  /// 点弹窗里的一个按钮（先滚动到可见）。
  Future<void> tapButton(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<WordRow> wordOf(int id) =>
      (db.select(db.words)..where((row) => row.id.equals(id))).getSingle();

  Future<WordContentRow> contentOf(int id) => (db.select(
    db.wordContents,
  )..where((row) => row.wordId.equals(id))).getSingle();

  testWidgets('文本未变化时提示可重新获取，并用原文本查询', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult('苹果');

    await open(tester, wordId: id);
    expect(find.textContaining('文本未变化'), findsOneWidget);

    await tapButton(tester, '获取有道词典内容');

    expect(lookup.lastCall!['term'], 'apple');
    expect(find.text('确认应用并保存词条'), findsOneWidget);
  });

  testWidgets('改文本后提示需重新初始化，并用新文本查询', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult('梨');

    await open(tester, wordId: id);
    await tester.enterText(find.byType(TextField), 'Pear');
    await tester.pumpAndSettle();
    expect(find.textContaining('已修改'), findsOneWidget);

    await tapButton(tester, '获取有道词典内容');

    expect(lookup.lastCall!['term'], 'Pear');
  });

  testWidgets('确认应用后词条文本与内容一起落库', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult('梨');
    var saved = false;

    await open(tester, wordId: id, onSaved: () => saved = true);
    await tester.enterText(find.byType(TextField), 'pear');
    await tester.pumpAndSettle();
    await tapButton(tester, '获取有道词典内容');
    await tapButton(tester, '确认应用并保存词条');

    expect(saved, isTrue);
    final word = await wordOf(id);
    expect(word.term, 'pear');
    expect(word.normalizedTerm, 'pear');
    expect((await contentOf(id)).definitionsJson, contains('梨'));
  });

  testWidgets('空文本时不能获取内容', (tester) async {
    final id = await insertWordRow(db);

    await open(tester, wordId: id);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '获取有道词典内容'),
    );
    expect(button.onPressed, isNull);
    expect(lookup.calls, 0);
  });

  testWidgets('有道没有内容时提示不能保存且不给确认按钮', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = DictionaryLookupResult(
      content: emptyDictionaryContent(),
      attempts: const <ProviderAttemptRecord>[
        ProviderAttemptRecord(
          providerId: 'youdao',
          status: ProviderAttemptStatus.failed,
          durationMs: 5,
          fieldsReturned: <String>[],
          errorMessage: '有道返回了空页面',
        ),
      ],
      hasTransientFailure: false,
      contentSource: ContentSource.dictionaryOnly,
    );

    await open(tester, wordId: id);
    await tapButton(tester, '获取有道词典内容');

    expect(find.text('有道词典未返回该词条的有效内容，暂不能保存修改。'), findsOneWidget);
    expect(find.text('有道返回了空页面'), findsOneWidget);
    expect(find.text('确认应用并保存词条'), findsNothing);
    expect((await wordOf(id)).term, 'apple');
  });

  testWidgets('改成已有词条时弹窗内报错且不落库', (tester) async {
    final id = await insertWordRow(db);
    await insertWordRow(db, term: 'banana');
    lookup.result = youdaoResult('香蕉');

    await open(tester, wordId: id);
    await tester.enterText(find.byType(TextField), 'banana');
    await tester.pumpAndSettle();
    await tapButton(tester, '获取有道词典内容');
    await tapButton(tester, '确认应用并保存词条');

    expect(find.text('已存在相同词条，无法修改为该文本。'), findsOneWidget);
    expect((await wordOf(id)).term, 'apple');
  });
}
