/// 有道词典获取弹窗的 widget 测试。
///
/// 钉住四种状态各自有出口，以及「应用」真的落库：
/// 旧版这一块最容易出的问题是弹窗只有加载态、出错后无法重试，
/// 或者确认按钮点了却没写库（看起来成功，实际什么都没发生）。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/dialogs/youdao_preview_dialog.dart';
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
  DictionaryLookupResult youdaoResult({
    List<Map<String, Object?>> definitions = const <Map<String, Object?>>[],
    List<Map<String, Object?>> examples = const <Map<String, Object?>>[],
  }) => DictionaryLookupResult(
    content: DictionaryContent(<String, Object?>{
      'definitions': definitions,
      'examples': examples,
      'summary': <String, Object?>{'translation': '苹果'},
      'pronunciations': <Object?>[
        <String, Object?>{'accent': 'US', 'phonetic': 'ˈæpl'},
      ],
      'forms': <Object?>[
        <String, Object?>{'type': 'PLURAL', 'value': 'apples'},
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

  List<Override> overrides() => <Override>[
    databaseProvider.overrideWithValue(db),
    wordContentRefreshServiceProvider.overrideWithValue(
      WordContentRefreshService(
        db,
        SettingsService(SettingsDao(db)),
        lookup,
        WordEditService(db),
      ),
    ),
  ];

  /// 把测试画布调高，让弹窗里的预览与按钮都落在可点区域内。
  ///
  /// 预览区自带 `maxHeight`，默认 800x600 的画布下「确认应用」会被挤出
  /// 可视区，`tap` 会静默打空（只给一条 warnIfMissed 警告）。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 打开弹窗的宿主页面。
  Widget host(int wordId, {VoidCallback? onApplied}) => wrapWithScope(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => YoudaoPreviewDialog.show(
          context,
          wordId: wordId,
          onApplied: onApplied,
        ),
        child: const Text('打开'),
      ),
    ),
    overrides: overrides(),
  );

  /// 打开弹窗并等待加载结束。
  Future<void> open(
    WidgetTester tester,
    int wordId, {
    VoidCallback? onApplied,
  }) async {
    useTallViewport(tester);
    await tester.pumpWidget(host(wordId, onApplied: onApplied));
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

  Future<WordContentRow> contentOf(int id) => (db.select(
    db.wordContents,
  )..where((row) => row.wordId.equals(id))).getSingle();

  testWidgets('加载中显示获取提示', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult();

    await tester.pumpWidget(host(id));
    await tester.tap(find.text('打开'));
    await tester.pump();

    expect(find.text('正在从有道词典获取内容…'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('有内容时按分区预览并展示应用方式', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult(
      definitions: <Map<String, Object?>>[
        <String, Object?>{'language': 'zh', 'text': '苹果', 'partOfSpeech': 'n.'},
      ],
      examples: <Map<String, Object?>>[
        <String, Object?>{
          'sentence': 'An apple a day.',
          'translation': '一天一苹果。',
        },
      ],
    );

    await open(tester, id);

    expect(find.text('翻译摘要'), findsOneWidget);
    expect(find.text('苹果'), findsWidgets);
    expect(find.text('释义'), findsOneWidget);
    expect(find.text('例句'), findsOneWidget);
    expect(find.text('短语搭配'), findsNothing, reason: '空分区整块不出现');
    expect(find.text('词形变化'), findsOneWidget);
    expect(find.text('复数: apples'), findsOneWidget);
    expect(find.text('应用方式'), findsOneWidget);
    expect(find.text('仅补全缺失字段'), findsOneWidget);
    expect(find.text('覆盖替换'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认应用'), findsOneWidget);
  });

  testWidgets('确认应用后落库并关闭弹窗', (tester) async {
    final id = await insertWordRow(db);
    lookup.result = youdaoResult(
      definitions: <Map<String, Object?>>[
        <String, Object?>{'language': 'zh', 'text': '苹果'},
      ],
      examples: <Map<String, Object?>>[
        <String, Object?>{'sentence': 'An apple a day.'},
      ],
    );
    var applied = false;

    await open(tester, id, onApplied: () => applied = true);
    await tapButton(tester, '确认应用');

    expect(applied, isTrue);
    expect(find.text('确认应用'), findsNothing);
    final content = await contentOf(id);
    expect(content.definitionsJson, contains('苹果'));
    expect(content.examplesJson, contains('An apple a day.'));
    expect(content.contentSource, ContentSource.dictionaryOnly);
    final word = await (db.select(
      db.words,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(word.initializationStatus, InitializationStatus.ready);
  });

  testWidgets('选「覆盖替换」时保留手动编辑的释义与手动添加的例句', (tester) async {
    final id = await insertWordRow(
      db,
      definitionsJson: jsonEncode(<Object?>[
        <String, Object?>{
          'language': 'zh',
          'text': '我写的',
          'isUserEdited': true,
        },
        <String, Object?>{'language': 'zh', 'text': '旧释义'},
      ]),
      examplesJson: jsonEncode(<Object?>[
        <String, Object?>{'sentence': 'My sentence.', 'isUserAdded': true},
        <String, Object?>{'sentence': 'Old sentence.'},
      ]),
    );
    lookup.result = youdaoResult(
      definitions: <Map<String, Object?>>[
        <String, Object?>{'language': 'zh', 'text': '词典新释义'},
      ],
      examples: <Map<String, Object?>>[
        <String, Object?>{'sentence': 'Dictionary sentence.'},
      ],
    );

    await open(tester, id);
    await tapButton(tester, '覆盖替换');
    await tapButton(tester, '确认应用');

    final content = await contentOf(id);
    expect(content.definitionsJson, contains('我写的'));
    expect(content.definitionsJson, contains('词典新释义'));
    expect(content.definitionsJson, isNot(contains('旧释义')));
    expect(content.examplesJson, contains('My sentence.'));
    expect(content.examplesJson, contains('Dictionary sentence.'));
    expect(content.examplesJson, isNot(contains('Old sentence.')));
  });

  testWidgets('无内容时列出各次尝试的错误说明且不给确认按钮', (tester) async {
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

    await open(tester, id);

    expect(find.text('有道词典未返回该词条的有效内容。'), findsOneWidget);
    expect(find.text('有道返回了空页面'), findsOneWidget);
    expect(find.text('确认应用'), findsNothing);
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('出错时给出关闭与重试，重试后能拿到内容', (tester) async {
    final id = await insertWordRow(db);
    var failFirst = true;
    final flaky = _FlakyWordLookup(
      onLookup: () {
        if (failFirst) {
          failFirst = false;
          throw const ExternalServiceError(AppErrorCode.networkUnavailable);
        }
        return youdaoResult(
          definitions: <Map<String, Object?>>[
            <String, Object?>{'language': 'zh', 'text': '苹果'},
          ],
        );
      },
    );
    final scope = wrapWithScope(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => YoudaoPreviewDialog.show(context, wordId: id),
          child: const Text('打开'),
        ),
      ),
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        wordContentRefreshServiceProvider.overrideWithValue(
          WordContentRefreshService(
            db,
            SettingsService(SettingsDao(db)),
            flaky,
            WordEditService(db),
          ),
        ),
      ],
    );

    useTallViewport(tester);
    await tester.pumpWidget(scope);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('网络不可用。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tapButton(tester, '重试');

    expect(find.text('确认应用'), findsOneWidget);
    expect(find.text('苹果'), findsWidgets);
  });
}

/// 按回调决定成功或抛错的假词典。
class _FlakyWordLookup implements WordLookup {
  new({required this.onLookup});

  final DictionaryLookupResult Function() onLookup;

  @override
  Future<DictionaryLookupResult> lookup({
    required dynamic settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  }) async => onLookup();
}
