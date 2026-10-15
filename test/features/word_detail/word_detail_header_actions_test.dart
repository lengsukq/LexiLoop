/// 词条详情页头部操作与发音接线的 widget 测试。
///
/// 钉住三件事：两个初始化按钮真的按各自模式入队、朗读走 `WordSpeaker`
/// 而不是直接调 `TtsService`、真人录音开关按设置同步。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/word_detail/word_detail_page.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

import '../../support/app_harness.dart';
import 'word_write_test_support.dart';

void main() {
  late AppDatabase db;
  late RecordingSpeaker speaker;
  late FakeWordLookup lookup;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    speaker = RecordingSpeaker();
    lookup = FakeWordLookup();
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 打开词条详情页。
  Future<void> open(WidgetTester tester, int wordId) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      wrapWithScope(
        WordDetailPage(wordId: wordId),
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          wordSpeakerProvider.overrideWithValue(speaker),
          // 有道预览会联网：换成假词典，测试不发任何真实请求。
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

  Future<List<InitializationJobRow>> jobs() =>
      db.select(db.initializationJobs).get();

  testWidgets('头部展示补全、有道、编辑、重新生成与删除入口', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    expect(find.text('补全缺失内容'), findsOneWidget);
    expect(find.text('有道词典'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('「补全缺失内容」按只补空缺入队', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('补全缺失内容'));
    await tester.pumpAndSettle();

    final queued = await jobs();
    expect(queued, hasLength(1));
    expect(queued.single.wordId, id);
    expect(queued.single.taskType, JobTaskType.initialize);
    expect(queued.single.mode, InitializationMode.fillMissingFields);
    expect(queued.single.priority, jobPriorityDefault);
    expect(find.text('已排入补全队列'), findsOneWidget);
  });

  testWidgets('「重新生成」二次确认后按覆盖模式入队', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(find.text('重新生成会再次调用 AI，但会保留手动释义和例句。确定继续吗？'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    final queued = await jobs();
    expect(queued, hasLength(1));
    expect(queued.single.mode, InitializationMode.forceOverwrite);
    expect(find.text('已排入重新生成队列'), findsOneWidget);
  });

  testWidgets('取消重新生成时不入队', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await jobs(), isEmpty);
  });

  testWidgets('朗读走 WordSpeaker 并带上词条与音标', (tester) async {
    final id = await insertWordRow(
      db,
      pronunciationsJson:
          '[{"accent":"US","phonetic":"ˈæpl","source":"youdao"}]',
    );
    await open(tester, id);

    await tester.tap(find.byTooltip('朗读'));
    await tester.pumpAndSettle();

    expect(speaker.requests, hasLength(1));
    final request = speaker.requests.single;
    expect(request.term, 'apple');
    expect(request.contentType, LexicalContentType.word);
    expect(request.pronunciations, hasLength(1));
    expect(request.pronunciations.single.phonetic, 'ˈæpl');
  });

  testWidgets('设置关掉真人录音后同步到 speaker', (tester) async {
    final id = await insertWordRow(db);
    await SettingsDao(db)
        .saveAll(<String, Object?>{'humanAudioEnabled': false}, now);
    await open(tester, id);

    expect(speaker.humanAudioEnabled, isTrue, reason: '未点朗读前不该被动改状态');
    await tester.tap(find.byTooltip('朗读'));
    await tester.pumpAndSettle();

    expect(speaker.humanAudioEnabled, isFalse);
  });

  testWidgets('缺少中文译文时给出 AI 翻译释义入口并入队', (tester) async {
    final id = await insertWordRow(
      db,
      definitionsJson: '[{"language":"en","text":"a fruit"}]',
      summaryJson: '{"shortDefinition":"a round fruit"}',
    );
    await open(tester, id);

    expect(find.text('暂无中文释义'), findsOneWidget);
    await tester.tap(find.text('AI 翻译释义'));
    await tester.pumpAndSettle();

    final queued = await jobs();
    expect(queued, hasLength(1));
    expect(queued.single.taskType, JobTaskType.exampleTranslations);
    expect(find.text('已加入翻译队列'), findsOneWidget);
  });

  testWidgets('已有中文译文时不显示翻译入口', (tester) async {
    final id = await insertWordRow(
      db,
      summaryJson: '{"shortDefinition":"a fruit","translation":"一种水果"}',
    );
    await open(tester, id);

    expect(find.text('AI 翻译释义'), findsNothing);
  });

  testWidgets('删除词条需二次确认', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除词条'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(await db.select(db.words).get(), isEmpty);
  });

  testWidgets('有声明的暂停开关仍可用', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    expect(find.byType(Switch), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final word = await (db.select(
      db.words,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(word.isSuspended, isTrue);
  });

  testWidgets('打开编辑弹窗', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('编辑词条'), findsOneWidget);
    expect(find.text('词条文本'), findsOneWidget);
  });

  testWidgets('打开有道词典弹窗', (tester) async {
    final id = await insertWordRow(db);
    await open(tester, id);

    await tester.tap(find.text('有道词典'));
    await tester.pump();
    await tester.pump();

    expect(find.text('有道词典获取'), findsOneWidget);
  });
}
