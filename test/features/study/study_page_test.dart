/// 学习会话界面的 widget 测试。
///
/// 全部用内存数据库驱动真实服务（`StudyService` / `ReviewService`），
/// 只把 `databaseProvider` 换成内存实例。这样测的是「界面 + 服务 + SQL」
/// 的完整链路，而不是一个被 mock 到只剩渲染的页面。
///
/// **会话是怎么被页面接上的**：种子数据直接写一条 `session_type = DAILY`、
/// `started_at` 为当前时刻、且含 PENDING 题目的会话；页面启动时
/// `StudyService.startSession` 会把它当作可恢复会话读回来，因此题目类型、
/// 选项、挖空句都由真实 DAO 生成，测试不必伪造 [StudyItemView]。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/services/tts_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../services/audio/audio_fakes.dart';

/// 记录朗读文本的假引擎。
class RecordingSpeechEngine implements SpeechEngine {
  /// 已朗读的文本。
  final List<String> spoken = <String>[];

  @override
  Future<void> configure({
    required double rate,
    required String language,
  }) async {}

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;
}

/// 读取富文本某一行的纯文本。
String _plainText(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).textSpan!.toPlainText();

/// 读取富文本某一行里被标为差异（带下划线）的片段。
List<String> _diffParts(WidgetTester tester, Key key) {
  final span = tester.widget<Text>(find.byKey(key)).textSpan! as TextSpan;
  return <String>[
    for (final child in span.children!.whereType<TextSpan>())
      if (child.style?.decoration == TextDecoration.underline) child.text!,
  ];
}

void main() {
  late AppDatabase db;
  late FakeAudioPlayer audioPlayer;
  late FakeAudioDownloader audioDownloader;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    audioPlayer = FakeAudioPlayer();
    audioDownloader = FakeAudioDownloader()..openGate();
  });

  tearDown(() => db.close());

  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 插入一个可学习词条（READY + 一条中文释义），返回词条 ID。
  Future<int> insertWord({
    required String term,
    required String meaning,
    String examplesJson = '[]',
    String? pronunciationsJson,
  }) async {
    final stamp = nowMs();
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
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(
              '[{"language":"zh","text":"$meaning"}]',
            ),
            examplesJson: Value<String>(examplesJson),
            pronunciationsJson: Value<String>(pronunciationsJson ?? '[]'),
            updatedAt: stamp,
          ),
        );
    return id;
  }

  /// 一条带美音真人录音的发音 JSON。
  String pronunciationJson(String audioUrl) =>
      '[{"accent":"US","phonetic":"test",'
      '"audioUrl":"$audioUrl","source":"youdao"}]';

  /// 往会话里追加一道题。
  Future<void> addSessionItem({
    required int sessionId,
    required double position,
    required int wordId,
    required QuestionType questionType,
  }) async {
    final stamp = nowMs();
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: position,
            wordId: wordId,
            taskType: StudyTaskType.review,
            questionType: questionType,
            createdAt: stamp,
          ),
        );
  }

  /// 建一条含单道题目的「今日」会话，返回会话 ID。
  ///
  /// `started_at` 必须取当前时刻：学习页会先尝试恢复未完成会话，
  /// 超过 `sessionResumeTtlMs` 的会话已被判过期，不会被恢复。
  Future<int> insertSession({
    required int wordId,
    required QuestionType questionType,
  }) async {
    final stamp = nowMs();
    final sessionId = await db
        .into(db.studySessions)
        .insert(
          StudySessionsCompanion.insert(
            sessionType: StudyMode.daily,
            startedAt: stamp,
            plannedCount: const Value<int>(1),
            createdAt: stamp,
          ),
        );
    await addSessionItem(
      sessionId: sessionId,
      position: 0,
      wordId: wordId,
      questionType: questionType,
    );
    return sessionId;
  }

  /// 挂载学习页并等待会话加载完成，返回 provider 容器。
  ///
  /// 画布刻意设得又窄又高：默认 800×600 装不下「题干 + 作答 + 自评 +
  /// 反馈」，而 `ListView` 不会挂载视口外的子组件，finder 会找不到它们。
  ///
  /// 三个覆盖是硬要求：
  /// - `audioPlayerPortProvider`：`just_audio` 是平台通道插件，测试进程里不可用；
  /// - `audioDownloaderProvider`：假下载器，**不发真实网络请求**；
  /// - `studyClockFactoryProvider`：活跃计时器的 `Timer` 走假时间，
  ///   不注入 `binding.clock` 就会与 `DateTime.now()` 各走一套时间。
  Future<ProviderContainer> pumpStudy(
    WidgetTester tester, {
    StudyMode mode = StudyMode.daily,
    SpeechEngine? speechEngine,
    IntervalPreviewLoader? intervalPreviewLoader,
  }) async {
    tester.view.physicalSize = const Size(520, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioPlayerPortProvider.overrideWithValue(audioPlayer),
        audioDownloaderProvider.overrideWithValue(audioDownloader),
        studyClockFactoryProvider.overrideWithValue(
          () => StudyClock(
            now: () => tester.binding.clock.now().millisecondsSinceEpoch,
          ),
        ),
        if (speechEngine != null)
          ttsServiceProvider.overrideWithValue(TtsService(speechEngine)),
        if (intervalPreviewLoader != null)
          intervalPreviewLoaderProvider.overrideWithValue(
            intervalPreviewLoader,
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // 必须挂上应用主题：`context.lexiColors` 依赖 [LexiTheme] 注入的
        // ThemeExtension，裸 MaterialApp 会直接空断言崩溃。
        child: MaterialApp(
          theme: LexiTheme.light,
          home: StudyPage(mode: mode),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 读回页面当前持有的会话视图。
  StudySessionView sessionOf(ProviderContainer container) =>
      container.read(studySessionProvider).value!;

  testWidgets('没有候选词条时走结算视图，标题与做完一轮不同', (tester) async {
    // 「今天没词可学」与「刚做完一轮」共用结算视图，只有标题不同——
    // 照旧版 `study-client.tsx:548`。曾经这里是一个独立的空态页，
    // 整页只剩一个 `maybePop` 的返回按钮，而学习页是分支根路由，
    // 那个按钮点了没反应，用户被困在沉浸式页面里（见下一条用例）。
    await pumpStudy(tester);

    expect(find.text('暂时没有更多可学习词条'), findsOneWidget);
    expect(find.text('这一轮完成了'), findsNothing);
    // 空态也必须给得出「再来一轮」，否则导入词条后只能退出重进。
    expect(find.text('再来一轮'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });

  testWidgets('会话启动失败时显示错误态与重试', (tester) async {
    // AI 推荐模式在没有当日建议时直接抛 ConflictError，是最容易构造的失败路径。
    await pumpStudy(tester, mode: StudyMode.aiRecommended);

    expect(find.text('今日 AI 必做题已全部完成，明天再来吧。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('看词选义渲染出全部选项', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    for (final entry in <(String, String)>[
      ('banana', '香蕉'),
      ('cherry', '樱桃'),
      ('grape', '葡萄'),
      ('lemon', '柠檬'),
    ]) {
      await insertWord(term: entry.$1, meaning: entry.$2);
    }
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    final container = await pumpStudy(tester);
    final choices = sessionOf(container).items.first.choices;

    expect(choices, hasLength(4), reason: '干扰项足够时应凑满 4 个选项');
    for (final choice in choices) {
      expect(find.text(choice), findsOneWidget);
    }
    expect(find.text('apple'), findsOneWidget, reason: '题干是英文词条');
  });

  testWidgets('看义选词在选项下显示对应释义', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertWord(term: 'banana', meaning: '香蕉');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.zhToEnChoice,
    );

    final container = await pumpStudy(tester);
    final item = sessionOf(container).items.first;

    expect(item.choices, isNotEmpty);
    for (final choice in item.choices) {
      expect(find.text(choice), findsOneWidget);
    }
    // 题干是「苹果」，正确选项 `apple` 的释义也是「苹果」，因此出现两次。
    expect(find.text('苹果'), findsNWidgets(2));
    expect(find.text('香蕉'), findsOneWidget, reason: '干扰项也要带释义');
  });

  testWidgets('选中选项后点自评即提交并显示判定', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertWord(term: 'banana', meaning: '香蕉');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    final container = await pumpStudy(tester);
    expect(find.text('回答正确'), findsNothing, reason: '提交前没有判定结果');

    await tester.tap(find.text('苹果'));
    await tester.pump();
    // 自评按钮就是提交入口：旧版交互是「先作答，再选记得程度」。
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    expect(find.text('回答正确'), findsOneWidget);
    expect(sessionOf(container).completedCount, 1);
  });

  testWidgets('提交后自评四档收起，误触不会重复推进', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertWord(term: 'banana', meaning: '香蕉');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    final container = await pumpStudy(tester);
    await tester.tap(find.text('苹果'));
    await tester.pump();
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    // 提交后整排自评收起：既点不动，也不可能被误触产生第二次作答。
    // 这一排此前是「变灰但仍占位」，判定与「下一题」被推到折叠线之外，
    // 用户按完回车只看到按钮灰掉。收起来同时解决两个问题。
    for (final label in <String>['忘了', '模糊', '简单']) {
      expect(find.text(label), findsNothing, reason: '$label 提交后应当收起');
    }
    expect(sessionOf(container).completedCount, 1);

    // 判定与「下一题」就在原地，不必滚到下面去找。
    expect(find.text('下一题'), findsOneWidget);
  });

  testWidgets('答错时反馈区显示期望答案', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertWord(term: 'banana', meaning: '香蕉');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    await pumpStudy(tester);
    await tester.tap(find.text('香蕉'));
    await tester.pump();
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    expect(find.text('回答错误'), findsOneWidget);
    expect(find.text('期望答案：苹果'), findsOneWidget);
  });

  testWidgets('中译英拼写正确时判定为正确', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.zhToEnSpelling,
    );

    await pumpStudy(tester);
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.pump();
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    expect(find.text('回答正确'), findsOneWidget);
  });

  testWidgets('四档自评在作答期间可见，提交后交给判定面板', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.zhToEnSpelling,
    );

    await pumpStudy(tester);
    for (final label in <String>['忘了', '模糊', '记得', '简单']) {
      expect(find.text(label), findsOneWidget, reason: '四档始终可见，用户才知道有哪些选择');
    }
    expect(find.text('先作答，再选择记得程度'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'apple');
    await tester.pump();
    expect(find.text('你记得怎么样？'), findsOneWidget);

    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    // 提交后这一排由判定面板接替；自评分数仍在面板里写出来
    // （「自评：记得」），所以收起并不丢信息。
    expect(find.text('已记录的等级'), findsNothing);
    expect(find.textContaining('回答'), findsWidgets);
    expect(find.text('下一题'), findsOneWidget);
  });

  testWidgets('看词说义点自评即提交', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

    await pumpStudy(tester);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('你记得怎么样？'), findsOneWidget, reason: '主观题无需先作答');

    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    expect(find.text('回答正确'), findsOneWidget);
  });

  testWidgets('字母拼词可拼出单词并退格', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(wordId: wordId, questionType: QuestionType.letterBank);

    await pumpStudy(tester);
    for (final letter in <String>['a', 'p', 'p']) {
      await tester.tap(find.text(letter).first);
      await tester.pump();
    }
    expect(find.text('app'), findsOneWidget);

    await tester.tap(find.text('退格'));
    await tester.pump();
    expect(find.text('ap'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('点击下方字母拼写'), findsOneWidget);
  });

  testWidgets('例句填空渲染出挖空句与翻译', (tester) async {
    final wordId = await insertWord(
      term: 'apple',
      meaning: '苹果',
      examplesJson:
          '[{"sentence":"I ate an apple.","translation":"我昨天吃了一个苹果。"}]',
    );
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.clozeSentence,
    );

    await pumpStudy(tester);

    expect(find.textContaining('____'), findsOneWidget);
    expect(find.text('我昨天吃了一个苹果。'), findsOneWidget);
  });

  testWidgets('朗读按钮可点，且把文本交给朗读服务', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    // 用假引擎替换真插件：平台通道在测试进程里不可用。
    final engine = RecordingSpeechEngine();
    final container = await pumpStudy(tester, speechEngine: engine);

    expect(find.byTooltip('朗读'), findsOneWidget);
    await tester.tap(find.byTooltip('朗读'));
    await tester.pumpAndSettle();

    expect(engine.spoken, <String>['apple']);
    expect(container.read(studySessionProvider).hasValue, isTrue);
  });

  testWidgets('完成态显示正确率与统计数字', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.zhToEnSpelling,
    );

    await pumpStudy(tester);
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.pump();
    await tester.tap(find.text('记得'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();

    expect(find.text('这一轮完成了'), findsOneWidget);
    expect(find.text('正确率'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('有效时长'), findsOneWidget);
    expect(find.text('再来一轮'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });

  testWidgets('跳过按钮推进到下一题并计入跳过数', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.zhToEnSpelling,
    );

    final container = await pumpStudy(tester);
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(sessionOf(container).skippedCount, 1);
    expect(find.text('这一轮完成了'), findsOneWidget);
  });

  group('间隔预览', () {
    testWidgets('四档按钮上显示各自的排期间隔', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester);
      await tester.pumpAndSettle();

      final previews = await container
          .read(reviewServiceProvider)
          .previewIntervals(wordId, now: nowMs());
      expect(previews, hasLength(4));
      for (final preview in previews) {
        expect(
          tester
              .widget<Text>(
                find.byKey(Key('study.rating.interval.${preview.rating.wire}')),
              )
              .data,
          studyIntervalText(preview.scheduledDays),
        );
      }
    });

    testWidgets('预览失败时不显示间隔，且不阻断答题', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(
        tester,
        intervalPreviewLoader: (wordId) async => throw StateError('预览失败'),
      );
      await tester.pumpAndSettle();

      for (final rating in ReviewRating.values) {
        expect(
          tester
              .widget<Text>(
                find.byKey(Key('study.rating.interval.${rating.wire}')),
              )
              .data,
          '—',
          reason: '取不到预览就显示占位符，不能假装有间隔',
        );
      }

      // 预览只是提示：拿不到也必须能照常作答。
      await tester.tap(find.text('苹果'));
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('回答正确'), findsOneWidget);
      expect(sessionOf(container).completedCount, 1);
    });
  });

  group('拼写提示', () {
    testWidgets('逐层揭开字母，并把「记得」降级为「模糊」', (tester) async {
      // 用长词：服务层对长词的单个手误仍然判对，降级规则才有发挥空间。
      final wordId = await insertWord(term: 'beautiful', meaning: '美丽的');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final container = await pumpStudy(tester);
      expect(find.text('b _ _ _ _ _ _ _ l'), findsOneWidget);

      await tester.tap(find.text('提示'));
      await tester.pump();
      expect(find.text('b e a _ _ _ _ _ l'), findsOneWidget);
      expect(find.text('已使用提示，本题将按「模糊」记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'beautifull');
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('回答正确'), findsOneWidget, reason: '单字母手误仍判对');
      expect(find.text('自评：模糊'), findsOneWidget, reason: '用了提示就降一档');
      expect(find.text('已使用提示，建议选择「模糊」'), findsOneWidget);
      expect(sessionOf(container).completedCount, 1);
    });

    testWidgets('没用提示时同样的答案按「记得」记录', (tester) async {
      final wordId = await insertWord(term: 'beautiful', meaning: '美丽的');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'beautifull');
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('自评：记得'), findsOneWidget);
    });

    testWidgets('换题后提示等级清零', (tester) async {
      final first = await insertWord(term: 'beautiful', meaning: '美丽的');
      final second = await insertWord(term: 'wonderful', meaning: '精彩的');
      final sessionId = await insertSession(
        wordId: first,
        questionType: QuestionType.zhToEnSpelling,
      );
      await addSessionItem(
        sessionId: sessionId,
        position: 1,
        wordId: second,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.tap(find.text('提示'));
      await tester.pump();
      expect(find.text('提示 (1)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'beautiful');
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一题'));
      await tester.pumpAndSettle();

      expect(find.text('提示'), findsOneWidget, reason: '新题回到基础提示');
      expect(find.text('提示 (1)'), findsNothing);
      expect(find.text('w _ _ _ _ _ _ _ l'), findsOneWidget);
    });
  });

  group('答案差异', () {
    testWidgets('答错时展示字符级差异', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'aple');
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('回答错误'), findsOneWidget);
      expect(find.text('期望答案：apple'), findsOneWidget);
      expect(_plainText(tester, const Key('study.diff.actual')), '你的输入：aple');
      expect(
        _plainText(tester, const Key('study.diff.expected')),
        '正确答案：apple',
      );
      expect(_diffParts(tester, const Key('study.diff.expected')), <String>[
        'p',
      ], reason: '漏掉的那个字母才是差异段');
      expect(_diffParts(tester, const Key('study.diff.actual')), isEmpty);
    });

    testWidgets('答对时不展示差异', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.byKey(const Key('study.diff.expected')), findsNothing);
    });
  });

  group('键盘快捷键', () {
    testWidgets('数字键 1-4 提交对应评级', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 1);
      expect(find.text('自评：记得'), findsOneWidget);
    });

    testWidgets('未作答时数字键无效（与按钮同一可用性）', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final container = await pumpStudy(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 0);
      expect(find.text('先作答，再选择记得程度'), findsOneWidget);
    });

    testWidgets('空格提交，S 跳过，R 重播发音', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final engine = RecordingSpeechEngine();
      final container = await pumpStudy(tester, speechEngine: engine);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pumpAndSettle();
      expect(engine.spoken, <String>['apple']);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
      expect(find.text('自评：记得'), findsOneWidget);
    });

    testWidgets('S 稍后再学', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();

      expect(sessionOf(container).skippedCount, 1);
      expect(find.text('这一轮完成了'), findsOneWidget);
    });

    testWidgets('输入框聚焦时空格、字母键让位给输入法，数字键仍可用', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final engine = RecordingSpeechEngine();
      final container = await pumpStudy(tester, speechEngine: engine);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 0, reason: '空格不得提交');
      expect(sessionOf(container).skippedCount, 0, reason: 'S 不得跳过');
      expect(engine.spoken, isEmpty, reason: 'R 不得触发朗读');

      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
      expect(find.text('自评：记得'), findsOneWidget);
    });
  });

  group('活跃计时', () {
    testWidgets('挂机超过 45 秒后作答只记录活跃上限', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester);
      await tester.pump(const Duration(seconds: 100));
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      expect(
        log.durationMs,
        activeIdleTimeoutMs,
        reason: '空闲定时器在 45 秒时关掉了活跃段，挂机时间不计入',
      );
    });

    testWidgets('挂机后再交互只累加真实活跃段', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      await pumpStudy(tester);
      await tester.pump(const Duration(seconds: 30));
      // 点选项本身也是一次交互：它把活跃段续到这一刻。
      await tester.tap(find.text('苹果'));
      // 之后 60 秒没有任何交互：只有前 45 秒算活跃。
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      const expected = 30 * secondMs + activeIdleTimeoutMs;
      expect(
        log.durationMs,
        inInclusiveRange(expected, expected + 500),
        reason: '墙钟走了 90 秒，只该记录 30 秒活跃 + 45 秒空闲容忍（余量留给 pumpAndSettle 帧步）',
      );
    });
  });

  group('发音预取', () {
    testWidgets('挂载时预取当前题及其后各题的真人录音', (tester) async {
      final first = await insertWord(
        term: 'apple',
        meaning: '苹果',
        pronunciationsJson: pronunciationJson('https://example.com/apple.mp3'),
      );
      final second = await insertWord(
        term: 'banana',
        meaning: '香蕉',
        pronunciationsJson: pronunciationJson('https://example.com/banana.mp3'),
      );
      final sessionId = await insertSession(
        wordId: first,
        questionType: QuestionType.enToZh,
      );
      await addSessionItem(
        sessionId: sessionId,
        position: 1,
        wordId: second,
        questionType: QuestionType.enToZh,
      );

      await pumpStudy(tester);
      await tester.pumpAndSettle();

      expect(
        audioDownloader.downloaded.map((uri) => uri.toString()).toList(),
        <String>[
          'https://example.com/apple.mp3',
          'https://example.com/banana.mp3',
        ],
      );
      expect(audioPlayer.playCount, 0, reason: '预取只下载，不播放');
    });

    testWidgets('降级到系统朗读时界面给出提示', (tester) async {
      // 词条没有真人录音地址：必然回落到系统朗读。
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final engine = RecordingSpeechEngine();
      await pumpStudy(tester, speechEngine: engine);

      await tester.tap(find.byTooltip('朗读'));
      await tester.pumpAndSettle();

      expect(engine.spoken, <String>['apple']);
      expect(find.text('暂无真人录音，已改用系统朗读'), findsOneWidget);
    });
  });
}
