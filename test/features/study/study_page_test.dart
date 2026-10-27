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
///
/// **流程断言围绕三相位**：作答 → 揭示 → 自评 → 自动下一题。任何一条用例
/// 都不再依赖「下一题」按钮或「自评：X」文案——它们已经不存在了。
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
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/services/review_service.dart';
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

/// 永远写库失败的服务，用来验证「提交失败留在揭示态」。
class _FailingReviewService extends ReviewService {
  new(super._database, super._settings);

  @override
  Future<ReviewOutcome> processAnswer(
    AnswerInput input, {
    required int now,
  }) async => throw StateError('数据库写入失败');
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
  /// 四个覆盖是硬要求：
  /// - `audioPlayerPortProvider`：`just_audio` 是平台通道插件，测试进程里不可用；
  /// - `audioDownloaderProvider`：假下载器，**不发真实网络请求**；
  /// - `ttsServiceProvider`：默认注入一个静音假引擎，自动朗读/朗读按钮都不会
  ///   打到平台通道；
  /// - `studyClockFactoryProvider`：活跃计时器的 `Timer` 走假时间，
  ///   不注入 `binding.clock` 就会与 `DateTime.now()` 各走一套时间。
  ///
  /// 设置默认「揭示延迟 0、自动朗读关」，让大多数用例不必等 2 秒；需要验证
  /// 这两个开关的用例显式打开。
  Future<ProviderContainer> pumpStudy(
    WidgetTester tester, {
    StudyMode mode = StudyMode.daily,
    SpeechEngine? speechEngine,
    IntervalPreviewLoader? intervalPreviewLoader,
    int choiceRevealDelaySeconds = 0,
    bool autoPlay = false,
    bool submitFails = false,
    StudyRevealContentLoader? studyRevealContentLoader,
    bool settle = true,
    Size size = const Size(520, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = appSettingsFromRaw(<String, Object?>{
      'choiceRevealDelaySeconds': choiceRevealDelaySeconds,
      'autoPlayPronunciation': autoPlay,
    });
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        audioPlayerPortProvider.overrideWithValue(audioPlayer),
        audioDownloaderProvider.overrideWithValue(audioDownloader),
        appSettingsProvider.overrideWith((ref) => settings),
        ttsServiceProvider.overrideWithValue(
          TtsService(speechEngine ?? RecordingSpeechEngine()),
        ),
        studyClockFactoryProvider.overrideWithValue(
          () => StudyClock(
            now: () => tester.binding.clock.now().millisecondsSinceEpoch,
          ),
        ),
        if (submitFails)
          reviewServiceProvider.overrideWith(
            (ref) => _FailingReviewService(
              ref.watch(databaseProvider),
              ref.watch(settingsServiceProvider),
            ),
          ),
        if (intervalPreviewLoader != null)
          intervalPreviewLoaderProvider.overrideWithValue(
            intervalPreviewLoader,
          ),
        if (studyRevealContentLoader != null)
          studyRevealContentLoaderProvider.overrideWithValue(
            studyRevealContentLoader,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // 只推进到会话加载与首帧 prep，不跑完选择题的倒计时。
      for (var frame = 0; frame < 10; frame += 1) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
    return container;
  }

  /// 读回页面当前持有的会话视图。
  StudySessionView sessionOf(ProviderContainer container) =>
      container.read(studySessionProvider).value!;

  /// 点「检查答案 / 显示答案」。
  Future<void> checkAnswer(WidgetTester tester) async {
    await tester.tap(find.textContaining('检查答案').last);
    await tester.pumpAndSettle();
  }

  group('作答与揭示', () {
    testWidgets('没有候选词条时走结算视图，标题与做完一轮不同', (tester) async {
      // 「今天没词可学」与「刚做完一轮」共用结算视图，只有标题不同——
      // 照旧版 `study-client.tsx:548`。曾经这里是一个独立的空态页，
      // 整页只剩一个 `maybePop` 的返回按钮，而学习页是分支根路由，
      // 那个按钮点了没反应，用户被困在沉浸式页面里。
      await pumpStudy(tester);

      expect(find.text('暂时没有更多可学习词条'), findsOneWidget);
      expect(find.text('这一轮完成了'), findsNothing);
      expect(find.text('再来一轮'), findsOneWidget);
      expect(find.text('返回首页'), findsOneWidget);
    });

    testWidgets('会话启动失败时显示错误态与重试', (tester) async {
      // AI 推荐模式在没有当日建议时直接抛 ConflictError，是最容易构造的失败路径。
      await pumpStudy(tester, mode: StudyMode.aiRecommended);

      expect(find.text('今日 AI 必做题已全部完成，明天再来吧。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('看词选义渲染出全部选项与作答指令', (tester) async {
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
      final item = sessionOf(container).items.first;

      expect(item.choices, hasLength(4), reason: '干扰项足够时应凑满 4 个选项');
      for (final choice in item.choices) {
        expect(find.text(choice), findsOneWidget);
      }
      expect(find.text('apple'), findsOneWidget, reason: '题干是英文词条');
      expect(find.text('选择正确的释义'), findsOneWidget, reason: '题头说明该做什么');
    });

    testWidgets('看义选词揭示后才显示选项释义', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnChoice,
      );

      final container = await pumpStudy(tester);
      final item = sessionOf(container).items.first;

      expect(item.choices, isNotEmpty);
      // 作答前只给单词：释义留到揭示后再显示，避免选项本身把答案讲出来。
      expect(find.text('香蕉'), findsNothing);
      expect(find.text('苹果'), findsOneWidget, reason: '题干是中文释义');

      await tester.tap(find.text('apple'));
      await tester.pumpAndSettle();

      // 题干、正确选项下的释义、揭示面板里的释义各一次。
      expect(find.text('苹果'), findsNWidgets(3));
      expect(find.text('香蕉'), findsOneWidget, reason: '揭晓后干扰项也带释义');
    });

    testWidgets('选中选项即揭示，尚未写库', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester);
      final item = sessionOf(container).items.first;
      final correct = studyChoiceAnswer(item);
      expect(find.text('回答正确'), findsNothing, reason: '作答前没有判定');

      await tester.tap(find.text(correct));
      await tester.pumpAndSettle();

      // 揭示只做本地预览：还没有任何一条 review_log，也没有完成计数。
      expect(find.text('回答正确'), findsOneWidget);
      expect(sessionOf(container).completedCount, 0);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      // 自评条已经出现，但还没有「自评：X」这种转述。
      expect(find.text('记得'), findsOneWidget);
      expect(find.textContaining('自评：'), findsNothing);
    });

    testWidgets('揭示后自评即写库并自动进入下一题', (tester) async {
      final first = await insertWord(term: 'apple', meaning: '苹果');
      final second = await insertWord(term: 'banana', meaning: '香蕉');
      final sessionId = await insertSession(
        wordId: first,
        questionType: QuestionType.enToZhChoice,
      );
      await addSessionItem(
        sessionId: sessionId,
        position: 1,
        wordId: second,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester);
      final item = sessionOf(container).items.first;
      await tester.tap(find.text(studyChoiceAnswer(item)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 1);
      // 没有「下一题」可点：提交成功即前进到下一题。
      expect(find.text('下一题'), findsNothing);
      expect(find.text('banana'), findsOneWidget, reason: '下一题的题干');
      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.rating, ReviewRating.good);
      expect(log.isCorrect, isTrue);
    });

    testWidgets('答对后自评「忘了」不再出现自相矛盾的文案', (tester) async {
      // 截图回归：旧界面把客观的「回答正确」与主观的「自评：忘了」并排
      // 放在同一张卡里，还要求再点一次「下一题」。现在判定只出现在自评
      // 之前，提交后直接进入结算。
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester);
      final item = sessionOf(container).items.first;
      await tester.tap(find.text(studyChoiceAnswer(item)));
      await tester.pumpAndSettle();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('自评：忘了'), findsNothing);

      await tester.tap(find.text('忘了'));
      await tester.pumpAndSettle();

      expect(find.text('这一轮完成了'), findsOneWidget);
      expect(find.text('下一题'), findsNothing);
      expect(find.text('自评：忘了'), findsNothing);
      expect(find.text('掌握度'), findsNothing);
      expect(find.text('下次复习'), findsNothing);
      expect(sessionOf(container).completedCount, 1);

      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.isCorrect, isTrue, reason: '客观判题仍是答对');
      expect(log.rating, ReviewRating.again, reason: '自评仍是忘了');
    });

    testWidgets('答错时揭示面板显示期望答案与差异', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'aple');
      await tester.pump();
      await checkAnswer(tester);

      expect(find.text('回答错误'), findsOneWidget);
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

    testWidgets('忘记可以直接揭示，不必先作答', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final container = await pumpStudy(tester);
      expect(find.text('忘记'), findsOneWidget);
      await tester.tap(find.text('忘记'));
      await tester.pumpAndSettle();

      // 没有输入也能看到答案；判定是「回答错误」，但还没有写库。
      expect(find.text('回答错误'), findsOneWidget);
      expect(find.text('apple'), findsOneWidget);
      expect(sessionOf(container).completedCount, 0);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    });

    testWidgets('扩展助记内容只在揭示后加载并显示，查询失败不影响自评', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);
      var loads = 0;
      final container = await pumpStudy(
        tester,
        studyRevealContentLoader: (id) async {
          loads += 1;
          expect(id, wordId);
          return const StudyRevealContent(
            roots: <StudyRevealRoot>[
              StudyRevealRoot(root: 'ap', meaning: '远离'),
            ],
            affixes: <StudyRevealAffix>[
              StudyRevealAffix(
                value: '-le',
                meaning: '名词词尾',
                kind: AffixKind.suffix,
              ),
            ],
            mnemonic: '一个苹果',
          );
        },
      );

      expect(loads, 0);
      expect(find.text('助记与构词'), findsNothing);
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();

      expect(loads, 1);
      expect(find.text('助记与构词'), findsOneWidget);
      await tester.tap(find.text('助记与构词'));
      await tester.pumpAndSettle();
      expect(find.text('一个苹果'), findsOneWidget);
      expect(find.text('ap · 远离'), findsOneWidget);
      expect(find.text('-le · 名词词尾'), findsOneWidget);
      expect(sessionOf(container).completedCount, 0);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
    });

    testWidgets('扩展内容为空时不显示折叠区，且自评不受影响', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);
      final container = await pumpStudy(
        tester,
        studyRevealContentLoader: (_) async => const StudyRevealContent(),
      );

      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      expect(find.text('助记与构词'), findsNothing);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
    });

    testWidgets('扩展内容查询失败仍可完成揭示和自评', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);
      final container = await pumpStudy(
        tester,
        studyRevealContentLoader: (_) async =>
            throw StateError('lookup failed'),
      );

      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('助记与构词'), findsNothing);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
    });

    testWidgets('看词说义先显示答案再自评', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester);
      expect(find.text('显示答案'), findsOneWidget);
      expect(find.text('记得'), findsNothing, reason: '揭示前不摆自评');

      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();

      expect(find.text('参考答案'), findsOneWidget);
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('记得'), findsOneWidget);

      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      expect(find.text('这一轮完成了'), findsOneWidget);
    });

    testWidgets('拼写正确时揭示为回答正确', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();
      await checkAnswer(tester);

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.byKey(const Key('study.diff.expected')), findsNothing);
    });

    testWidgets('揭示面板折叠展示第一条例句', (tester) async {
      final wordId = await insertWord(
        term: 'apple',
        meaning: '苹果',
        examplesJson:
            '[{"sentence":"I ate an apple.","translation":"我吃了一个苹果。"}]',
      );
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester);
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();

      expect(find.text('例句'), findsOneWidget);
      expect(find.text('I ate an apple.'), findsNothing, reason: '默认折叠');
      await tester.tap(find.text('例句'));
      await tester.pumpAndSettle();
      expect(find.text('I ate an apple.'), findsOneWidget);
      expect(find.text('我吃了一个苹果。'), findsOneWidget);
    });

    testWidgets('四档自评只在揭示后出现', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      for (final label in <String>['忘了', '模糊', '记得', '简单']) {
        expect(find.text(label), findsNothing, reason: '$label 揭示前不应出现');
      }

      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();
      await checkAnswer(tester);

      for (final label in <String>['忘了', '模糊', '记得', '简单']) {
        expect(find.text(label), findsOneWidget, reason: '$label 揭示后应当可选');
      }
    });

    testWidgets('文本题回车检查答案', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester);
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('记得'), findsOneWidget);
    });

    testWidgets('字母拼词可拼出单词并退格', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.letterBank,
      );

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
      await checkAnswer(tester);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('这一轮完成了'), findsOneWidget);
      expect(find.text('正确率'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('有效时长'), findsOneWidget);
      expect(find.text('再来一轮'), findsOneWidget);
      expect(find.text('返回首页'), findsOneWidget);
    });

    testWidgets('稍后再学推进到下一题并计入跳过数', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final container = await pumpStudy(tester);
      expect(find.text('跳过'), findsNothing, reason: '页头不再有跳过');
      await tester.tap(find.text('稍后再学'));
      await tester.pumpAndSettle();

      expect(sessionOf(container).skippedCount, 1);
      expect(find.text('这一轮完成了'), findsOneWidget);
    });

    testWidgets('提交失败时留在揭示态并可重试', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester, submitFails: true);
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.textContaining('数据库写入失败'), findsOneWidget);
      // 没有前进：仍在当前题的揭示态，自评条可用。
      expect(find.text('参考答案'), findsOneWidget);
      expect(find.text('记得'), findsOneWidget);
      expect(sessionOf(container).completedCount, 0);
      expect(await db.select(db.reviewLogs).get(), isEmpty);

      // 让 SnackBar 的自动关闭定时器走完，避免测试结束时仍有挂起的 Timer。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('间隔预览', () {
    testWidgets('揭示后四档按钮上显示各自的排期间隔', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester);
      await tester.tap(find.text('显示答案'));
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

    testWidgets('预览失败时不显示间隔，且不阻断自评', (tester) async {
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
      final item = sessionOf(container).items.first;
      await tester.tap(find.text(studyChoiceAnswer(item)));
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

      // 预览只是提示：拿不到也必须能照常自评。
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
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
      await checkAnswer(tester);

      expect(find.text('回答正确'), findsOneWidget, reason: '单字母手误仍判对');
      expect(find.text('已使用提示，建议选择「模糊」'), findsOneWidget);

      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.rating, ReviewRating.hard, reason: '用了提示就降一档');
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
      await checkAnswer(tester);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.rating, ReviewRating.good);
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
      await checkAnswer(tester);
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      expect(find.text('提示'), findsOneWidget, reason: '新题回到基础提示');
      expect(find.text('提示 (1)'), findsNothing);
      expect(find.text('w _ _ _ _ _ _ _ l'), findsOneWidget);
    });
  });

  group('键盘快捷键', () {
    testWidgets('作答时数字键选选项，揭示后数字键才是自评', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester);
      final item = sessionOf(container).items.first;

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();

      // 数字键 1 在作答阶段只选第一个选项，不写库、不记自评。
      final options = tester.widget<ChoiceOptions>(find.byType(ChoiceOptions));
      expect(options.selected, item.choices.first);
      expect(options.revealed, isTrue);
      expect(sessionOf(container).completedCount, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.rating, ReviewRating.again);
    });

    testWidgets('文本题数字键不触发自评', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      final container = await pumpStudy(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 0);
      expect(find.text('检查答案'), findsOneWidget, reason: '仍在作答阶段');
    });

    testWidgets('空格两阶段：先揭示，再按记得', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      final container = await pumpStudy(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('参考答案'), findsOneWidget);
      expect(sessionOf(container).completedCount, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.rating, ReviewRating.good);
    });

    testWidgets('输入框聚焦时字母、空格、数字让位给输入法', (tester) async {
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
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();

      expect(sessionOf(container).completedCount, 0, reason: '空格不得提交');
      expect(sessionOf(container).skippedCount, 0, reason: 'S 不得跳过');
      expect(engine.spoken, isEmpty, reason: 'R 不得触发朗读');

      // 回车才是文本题的「检查答案」。
      await tester.enterText(find.byType(TextField), 'apple');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('回答正确'), findsOneWidget);

      // 揭示后输入框已卸载，数字键恢复为自评。
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect(sessionOf(container).completedCount, 1);
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
  });

  group('活跃计时', () {
    testWidgets('挂机超过 45 秒后揭示只记录活跃上限', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester);
      await tester.pump(const Duration(seconds: 100));
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      expect(
        log.durationMs,
        activeIdleTimeoutMs,
        reason: '空闲定时器在 45 秒时关掉了活跃段，挂机时间不计入',
      );
    });

    testWidgets('揭示后挑选自评的时间不计入作答时长', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      // 思考该选哪一档的 60 秒不属于「回忆这个词」的时间。
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      expect(
        log.durationMs,
        inInclusiveRange(9 * secondMs, 11 * secondMs),
        reason: '揭示时停表，自评等待不应计入',
      );
    });

    testWidgets('点选项也是一次交互，揭示后空闲不再累计', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester);
      await tester.pump(const Duration(seconds: 30));
      final item = sessionOf(container).items.first;
      await tester.tap(find.text(studyChoiceAnswer(item)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('记得'));
      await tester.pumpAndSettle();

      final log = await db.select(db.reviewLogs).getSingle();
      expect(
        log.durationMs,
        inInclusiveRange(30 * secondMs, 30 * secondMs + 500),
        reason: '只在作答段计时，揭示后的等待不计',
      );
    });
  });

  group('设置生效', () {
    testWidgets('揭示延迟：选项按设置延迟出现，可立即显示', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(
        tester,
        choiceRevealDelaySeconds: 2,
        settle: false,
      );
      final item = sessionOf(container).items.first;

      expect(find.text('2 秒后显示选项'), findsOneWidget);
      for (final choice in item.choices) {
        expect(find.text(choice), findsNothing, reason: '延迟期间不应看到选项');
      }

      await tester.tap(find.text('立即显示选项'));
      await tester.pumpAndSettle();
      for (final choice in item.choices) {
        expect(find.text(choice), findsOneWidget);
      }
    });

    testWidgets('揭示延迟到点后自动显示选项', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      await insertWord(term: 'banana', meaning: '香蕉');
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(
        tester,
        choiceRevealDelaySeconds: 2,
        settle: false,
      );
      final item = sessionOf(container).items.first;

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('立即显示选项'), findsNothing);
      for (final choice in item.choices) {
        expect(find.text(choice), findsOneWidget);
      }
    });

    testWidgets('自动朗读：看词选义会播放一次', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      final engine = RecordingSpeechEngine();
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      await pumpStudy(tester, autoPlay: true, speechEngine: engine);
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.spoken, <String>['apple']);
    });

    testWidgets('自动朗读：拼写题不播放（听完就等于拿到答案）', (tester) async {
      final wordId = await insertWord(term: 'banana', meaning: '香蕉');
      final engine = RecordingSpeechEngine();
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
      );

      await pumpStudy(tester, autoPlay: true, speechEngine: engine);
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.spoken, isEmpty);
    });

    testWidgets('关闭自动朗读时不播放', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      final engine = RecordingSpeechEngine();
      await insertSession(wordId: wordId, questionType: QuestionType.enToZh);

      await pumpStudy(tester, speechEngine: engine);
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.spoken, isEmpty);
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

  group('版面', () {
    testWidgets('窄屏下自评条吸底，内容再长也能直接操作', (tester) async {
      final wordId = await insertWord(term: 'apple', meaning: '苹果');
      for (final entry in <(String, String)>[
        ('banana', '香蕉'),
        ('cherry', '樱桃'),
        ('grape', '葡萄'),
      ]) {
        await insertWord(term: entry.$1, meaning: entry.$2);
      }
      await insertSession(
        wordId: wordId,
        questionType: QuestionType.enToZhChoice,
      );

      final container = await pumpStudy(tester, size: const Size(390, 640));
      final item = sessionOf(container).items.first;
      await tester.tap(find.text(studyChoiceAnswer(item)));
      await tester.pumpAndSettle();

      final rect = tester.getRect(find.text('记得'));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640), reason: '自评条必须吸底可见');
      expect(
        find.byType(SingleChildScrollView),
        findsWidgets,
        reason: '内容区应当可滚动',
      );
    });
  });
}
