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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_page.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 插入一个可学习词条（READY + 一条中文释义），返回词条 ID。
  Future<int> insertWord({
    required String term,
    required String meaning,
    String examplesJson = '[]',
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
            updatedAt: stamp,
          ),
        );
    return id;
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
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: 0,
            wordId: wordId,
            taskType: StudyTaskType.review,
            questionType: questionType,
            createdAt: stamp,
          ),
        );
    return sessionId;
  }

  /// 挂载学习页并等待会话加载完成，返回 provider 容器。
  ///
  /// 画布刻意设得又窄又高：默认 800×600 装不下「题干 + 作答 + 自评 +
  /// 反馈」，而 `ListView` 不会挂载视口外的子组件，finder 会找不到它们。
  Future<ProviderContainer> pumpStudy(
    WidgetTester tester, {
    StudyMode mode = StudyMode.daily,
  }) async {
    tester.view.physicalSize = const Size(520, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
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

  testWidgets('没有候选词条时显示空态', (tester) async {
    await pumpStudy(tester);

    expect(find.text('今天没有需要复习的词了'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
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

  testWidgets('提交后自评按钮禁用，重复点击不会重复推进', (tester) async {
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

    // 再点一次「记得」不应产生第二次作答。
    await tester.tap(find.text('记得'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(sessionOf(container).completedCount, 1);

    // 其余档位同样不可点。
    await tester.tap(find.text('简单'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(sessionOf(container).completedCount, 1);
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

  testWidgets('四档自评始终可见，作答后才可点', (tester) async {
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
    expect(find.text('已记录的等级'), findsOneWidget);
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

  testWidgets('朗读按钮已禁用并带说明', (tester) async {
    final wordId = await insertWord(term: 'apple', meaning: '苹果');
    await insertSession(
      wordId: wordId,
      questionType: QuestionType.enToZhChoice,
    );

    await pumpStudy(tester);

    // TTS 尚未接入：断言按钮存在且**禁用**，而不是断言点了有声音。
    expect(find.byTooltip('朗读功能待接入'), findsOneWidget);
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '朗读功能待接入',
      ),
    );
    expect(button.onPressed, isNull);
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
}
