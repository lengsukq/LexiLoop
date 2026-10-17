/// 结算页与音标错答的回归测试。
///
/// 这里钉住的是**四个「看起来能按、按下去什么也不发生」的缺陷**——
/// 它们都不是崩溃，也没有异常，所以既有的测试与静态分析全绿：
///
/// | 缺陷 | 曾表现 |
/// |---|---|
/// | 配对结算页「再来一局」调 `start()`，而 `start()` 要求当前是准备态 | 点击无反应，用户以为没点中 |
/// | 音标结算页同上 | 同上 |
/// | 音标错答后的选项区被禁用，而唯一能重选的动作不可达 | 界面文案说「重新选择」，实际只能「跳过」并记一次未完成 |
/// | 三个家族的 `resumeAfterSaveFailure()` 零调用 | 结算失败后只能重试或离开，离开就丢一轮 |
///
/// 因此每个用例都断言「这条路径真的动过状态 / 真的调到了那个回调」，
/// 而不是只断言界面上有某个文字。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/match/match_page.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/features/phonetics/phonetics_page.dart';
import 'package:lexiloop/features/phonetics/phonetics_play_view.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/phonetic_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../domain/games/random_source.dart';

/// 造一份结算结果。
GameResult buildResult(GameMode mode) {
  const summary = GameRoundSummary(
    answerScore: 520,
    firstTryCorrect: 4,
    recovered: 1,
    missed: 0,
    mistakeCount: 2,
    maxCombo: 3,
    elapsedMs: 42000,
    durationMs: 75000,
  );
  return GameResult(
    mode: mode,
    score: 520,
    summary: summary,
    rank: rankFor(score: 520, mode: mode),
    leaderboard: const GameLeaderboard(
      rank: 2,
      best: 900,
      top: <GameHighScore>[],
      isNewBest: false,
    ),
  );
}

/// 配对控制器：一构建就停在结算态，并给重开/开局各留一个计数器。
///
/// 覆盖 `start` 与 `restart` 是为了**分别**看见页面调的是哪一个：
/// 把 `restart` 换回 `start` 时，`starts` 会从 0 变成 1，用例立刻失败。
class _FinishedMatchController extends MatchController {
  /// `restart()` 被调用的次数。
  int restarts = 0;

  /// `start()` 被调用的次数。
  int starts = 0;

  @override
  MatchState build() => MatchFinished(result: buildResult(GameMode.match));

  @override
  Future<void> restart() async => restarts += 1;

  @override
  Future<void> start() async => starts += 1;
}

/// 音标控制器：同上。
class _FinishedPhoneticController extends PhoneticController {
  /// `restart()` 被调用的次数。
  int restarts = 0;

  /// `start()` 被调用的次数。
  int starts = 0;

  @override
  PhoneticState build() =>
      PhoneticFinished(result: buildResult(GameMode.phonetics));

  @override
  Future<void> restart() async => restarts += 1;

  @override
  Future<void> start() async => starts += 1;
}

/// 停在结算态、但**不覆盖** start/restart 的控制器。
///
/// 用它断言真实实现里的守卫语义：`start()` 从结算态调用必须原地返回，
/// `restart()` 必须真的把状态推出去。
class _UntouchedFinishedMatchController extends MatchController {
  @override
  MatchState build() => MatchFinished(result: buildResult(GameMode.match));
}

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: LexiTheme.light, home: home),
);

void main() {
  group('结算页「再来一局」', () {
    testWidgets('配对结算页走 restart()，不走只对准备态有效的 start()', (tester) async {
      final controller = _FinishedMatchController();
      await tester.pumpWidget(
        _app(const MatchPage(), <Override>[
          matchControllerProvider.overrideWith(() => controller),
        ]),
      );
      await tester.pump();

      await tester.tap(find.text('再来一局'));
      await tester.pump();

      expect(controller.restarts, 1);
      expect(controller.starts, 0, reason: 'start() 从结算态调用会被守卫拦下，等于按钮什么都不做');
    });

    testWidgets('音标结算页走 restart()，不走只对准备态有效的 start()', (tester) async {
      final controller = _FinishedPhoneticController();
      await tester.pumpWidget(
        _app(const PhoneticsPage(), <Override>[
          phoneticControllerProvider.overrideWith(() => controller),
        ]),
      );
      await tester.pump();

      await tester.tap(find.text('再来一局'));
      await tester.pump();

      expect(controller.restarts, 1);
      expect(controller.starts, 0);
    });

    test('start() 从结算态调用是空操作——这正是缺陷的根因', () async {
      final container = ProviderContainer(
        overrides: <Override>[
          matchControllerProvider.overrideWith(
            _UntouchedFinishedMatchController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final before = container.read(matchControllerProvider);
      expect(before, isA<MatchFinished>());

      await container.read(matchControllerProvider.notifier).start();

      expect(
        container.read(matchControllerProvider),
        same(before),
        reason: '这个「什么都没发生」就是用户按下去时的体验',
      );
    });

    test('restart() 从结算态调用会离开结算态', () async {
      // 用内存库让真实的 MatchingService 可用：空库会让开局以
      // 「词条不足」失败，但失败也是**状态变化**——本用例要的正是
      // 「不再静默」，而不是「能成功开一局」。
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          matchControllerProvider.overrideWith(
            _UntouchedFinishedMatchController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(matchControllerProvider.notifier).restart();

      expect(
        container.read(matchControllerProvider),
        isNot(isA<MatchFinished>()),
      );
    });
  });

  group('结算失败', () {
    testWidgets('除「重试」外还给出「继续本轮」，并把回调接上', (tester) async {
      var retried = 0;
      var resumed = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: GameErrorView(
              message: '结算失败：数据库忙',
              onRetry: () => retried += 1,
              secondaryLabel: resumeRoundLabel,
              onSecondary: () => resumed += 1,
            ),
          ),
          const <Override>[],
        ),
      );

      expect(find.text('重试'), findsOneWidget);
      expect(find.text(resumeRoundLabel), findsOneWidget);

      await tester.tap(find.text(resumeRoundLabel));
      await tester.pump();
      expect(resumed, 1);
      expect(retried, 0);
    });
  });

  group('音标错答', () {
    /// 造一份「已答错但未揭示」的进行中状态。
    PhoneticPlaying wrongSelectionState() {
      const plan = GamePlan(
        mode: GameMode.phonetics,
        itemCount: phoneticItemCount,
        durationMs: 75000,
      );
      final questions = buildPhoneticQuestions(
        sources: <PhoneticSource>[
          const PhoneticSource(
            itemId: 1,
            wordId: 1,
            word: GameWord(term: 'sheep', definition: '绵羊'),
            phonetic: '/ʃiːp/',
            priority: GamePriority.normal,
          ),
          const PhoneticSource(
            itemId: 2,
            wordId: 2,
            word: GameWord(term: 'ship', definition: '船'),
            phonetic: '/ʃɪp/',
            priority: GamePriority.normal,
          ),
          const PhoneticSource(
            itemId: 3,
            wordId: 3,
            word: GameWord(term: 'bed', definition: '床'),
            phonetic: '/bed/',
            priority: GamePriority.normal,
          ),
          const PhoneticSource(
            itemId: 4,
            wordId: 4,
            word: GameWord(term: 'bad', definition: '坏的'),
            phonetic: '/bæd/',
            priority: GamePriority.normal,
          ),
          const PhoneticSource(
            itemId: 5,
            wordId: 5,
            word: GameWord(term: 'food', definition: '食物'),
            phonetic: '/fuːd/',
            priority: GamePriority.normal,
          ),
        ],
        count: phoneticItemCount,
        random: constantRandom(),
      );
      // `startPhoneticQuiz` 只建出「准备开始」的状态，必须再派发
      // `StartPhoneticQuiz` 才进入 in-play——否则 `_choose` 会因为
      // `!core.isPlaying` 原地返回，用例的前置条件就永远不成立。
      final started = phoneticQuizNext(
        startPhoneticQuiz(plan: plan, questions: questions),
        const StartPhoneticQuiz(),
      );
      // 故意选一个错的选项：状态进入「答错但未揭示」。
      final wrong = questions.first.base.choices.options.firstWhere(
        (option) => option != questions.first.answer,
      );
      return PhoneticPlaying(
        session: PhoneticSession(
          sessionId: 1,
          plan: plan,
          questions: questions,
          accent: Accent.us,
        ),
        quiz: phoneticQuizNext(started, ChoosePhonetic(wrong)),
      );
    }

    testWidgets('错答后仍然存在一个能回到可作答状态的动作', (tester) async {
      final playing = wrongSelectionState();
      expect(
        playing.quiz.hasWrongSelection,
        isTrue,
        reason: '前置条件：一开始必须真的是错答未揭示的状态',
      );

      final actions = <PhoneticQuizAction>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PhoneticPlayView(
              playing: playing,
              onAction: actions.add,
              onExit: () {},
            ),
          ),
          const <Override>[],
        ),
      );
      await tester.pump();

      // 文案不再承诺一件做不到的事。
      expect(find.textContaining('再试一次'), findsWidgets);
      expect(find.byKey(phoneticRetryKey), findsOneWidget);

      await tester.tap(find.byKey(phoneticRetryKey));
      await tester.pump();

      expect(actions, hasLength(1));
      expect(actions.single, isA<ContinuePhonetic>());

      // 把动作真的喂回状态机：错答标记被清掉，于是可以重新作答。
      final after = phoneticQuizNext(playing.quiz, actions.single);
      expect(after.hasWrongSelection, isFalse);
      expect(after.revealed, isFalse);
    });
  });
}
