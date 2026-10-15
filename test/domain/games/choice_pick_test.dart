/// 听音辨词（LISTENING_PICK）与词义冲刺（MEANING_BLITZ）的规则、判题与状态机测试。
///
/// 这两个模式是旧版 `games/page.tsx` 里**内联**的两段题面（第 297-310 行），
/// 没有独立组件文件，因此第一轮迁移整个漏掉了它们。这里把「旧版真实存在的
/// 行为」逐条钉住：题量与时限、会话/题型/任务类型、排行榜 wire 值、
/// 词义冲刺的判题答案是释义、点错后红框期内不可作答。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/choice_pick.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/domain/games/word_builder.dart';

/// 造一道词义冲刺题：选项是释义，正确项也是释义。
GameQuestion meaningQuestion({
  int itemId = 1,
  String term = 'cat',
  String definition = '猫',
}) {
  return GameQuestion(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(term: term, definition: definition),
    choices: GameChoices(
      options: <String>[definition, '狗', '猪', '牛'],
      correct: definition,
    ),
    priority: GamePriority.normal,
  );
}

/// 造一道听音辨词题：选项是词形，正确项是词形。
GameQuestion listeningQuestion({
  int itemId = 1,
  String term = 'cat',
  String definition = '猫',
}) {
  return GameQuestion(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(term: term, definition: definition),
    choices: GameChoices(
      options: <String>[term, 'dog', 'pig', 'cow'],
      definitions: <String, String>{term: definition},
    ),
    priority: GamePriority.normal,
  );
}

/// 两道词义冲刺题的固定题面。
List<GameQuestion> twoMeaningQuestions() => <GameQuestion>[
  meaningQuestion(),
  meaningQuestion(itemId: 2, term: 'dog', definition: '狗'),
];

void main() {
  group('规则表', () {
    test('听音辨词的题量、时限与旧版 GAME_CONFIGS 一致', () {
      final session = rulesFor(GameMode.listeningPick).session;
      expect(session.itemCount, 8);
      expect(session.durationSeconds, 60);
      expect(session.sessionType, StudyMode.listening);
      expect(session.questionType, QuestionType.listeningSpelling);
      expect(session.taskType, StudyTaskType.listening);
      expect(
        rulesFor(GameMode.listeningPick).durationMs,
        listeningPickDurationSeconds * 1000,
      );
    });

    test('词义冲刺的题量、时限与旧版 GAME_CONFIGS 一致', () {
      final session = rulesFor(GameMode.meaningBlitz).session;
      expect(session.itemCount, 10);
      expect(session.durationSeconds, 45);
      expect(session.sessionType, StudyMode.daily);
      expect(session.questionType, QuestionType.enToZhChoice);
      expect(session.taskType, StudyTaskType.review);
      expect(
        rulesFor(GameMode.meaningBlitz).durationMs,
        meaningBlitzDurationSeconds * 1000,
      );
    });

    test('新模式不会静默回落到词汇地鼠的规则', () {
      // `rulesFor` 在表里缺项时会回落到 whackAMole；两个模式的题量与时限
      // 都与地鼠不同，一旦漏登记这条断言就会失败。
      final mole = rulesFor(GameMode.whackAMole).session;
      expect(
        rulesFor(GameMode.listeningPick).session.itemCount,
        isNot(mole.itemCount),
      );
      expect(
        rulesFor(GameMode.meaningBlitz).session.durationSeconds,
        isNot(mole.durationSeconds),
      );
      expect(
        rulesFor(GameMode.listeningPick).session.sessionType,
        isNot(mole.sessionType),
      );
    });

    test('wire 值与旧版逐字一致，历史高分才能归类', () {
      expect(GameMode.listeningPick.wire, 'LISTENING_PICK');
      expect(GameMode.meaningBlitz.wire, 'MEANING_BLITZ');
      expect(GameMode.listeningPick.sourceType, 'GAME_LISTENING_PICK');
      expect(GameMode.meaningBlitz.sourceType, 'GAME_MEANING_BLITZ');
      expect(GameMode.listeningPick.isMiniGame, isTrue);
      expect(GameMode.meaningBlitz.isMiniGame, isTrue);
    });

    test('计分沿用六个小游戏共用的那一套权重', () {
      for (final mode in <GameMode>[
        GameMode.listeningPick,
        GameMode.meaningBlitz,
      ]) {
        final rules = rulesFor(mode);
        expect(rules.score.basePoints, gameBasePoints);
        expect(rules.score.comboStep, gameComboStep);
        expect(rules.score.mistakePenalty, gameMistakePenalty);
        expect(rules.timeBonus.divisorMs, 0, reason: '不按剩余时间加分');
      }
    });
  });

  group('判题答案', () {
    test('词义冲刺的答案是释义，听音辨词的答案是词形', () {
      expect(meaningQuestion().answer, '猫');
      expect(listeningQuestion().answer, 'cat');
    });
  });

  group('选择题状态机', () {
    ChoicePickState start({
      int itemCount = 2,
      int durationSeconds = 45,
      List<GameQuestion>? questions,
    }) {
      return choicePickNext(
        startChoicePick(
          plan: gamePlanFor(
            GameMode.meaningBlitz,
            itemCount: itemCount,
            durationSeconds: durationSeconds,
          ),
          questions: questions ?? twoMeaningQuestions(),
        ),
        const StartChoicePick(),
      );
    }

    test('初始是 ready，开始后进入 playing', () {
      final ready = startChoicePick(
        plan: gamePlanFor(GameMode.meaningBlitz),
        questions: twoMeaningQuestions(),
      );
      expect(ready.core.progress.phase, GamePhase.ready);
      expect(ready.current, isNotNull);
      expect(
        choicePickNext(ready, const StartChoicePick()).core.isPlaying,
        isTrue,
      );
    });

    test('点对：记为一次答对、连击 +1、等待推进', () {
      final state = choicePickNext(start(), const PickChoice('猫'));
      expect(state.solved, isTrue);
      expect(state.core.outcomeFor(1), GameOutcome.firstTry);
      expect(state.core.tally.combo, 1);
      expect(state.isLocked, isTrue, reason: '反馈期内锁定选项');
    });

    test('点错：记一次失误、连击清零、红框期内不可再点', () {
      var state = choicePickNext(start(), const PickChoice('狗'));
      expect(state.core.tally.mistakeCount, 1);
      expect(state.core.tally.combo, 0);
      expect(state.wrongChoice, '狗');
      expect(state.isLocked, isTrue);
      expect(state.solved, isFalse);

      // 红框期内再点正确的选项也不会生效——旧版 `chooseAnswer` 开头就
      // `if (wrongChoice) return`，连点不会把同一个错误刷成一串失误。
      final locked = choicePickNext(state, const PickChoice('猫'));
      expect(locked.core.records.isSolved(1), isFalse);
      expect(locked.core.tally.mistakeCount, 1);

      state = choicePickNext(
        locked,
        const TickChoicePick(gameWrongChoiceFeedbackMs),
      );
      expect(state.isLocked, isFalse);
      expect(state.wrongChoice, isNull);
    });

    test('点错后再点对算「纠正完成」', () {
      var state = choicePickNext(start(), const PickChoice('狗'));
      state = choicePickNext(
        state,
        const TickChoicePick(gameWrongChoiceFeedbackMs),
      );
      state = choicePickNext(state, const PickChoice('猫'));
      expect(state.core.outcomeFor(1), GameOutcome.recovered);
      expect(state.solved, isTrue);
    });

    test('红框反馈按时间递减，未归零时仍然锁定', () {
      var state = choicePickNext(start(), const PickChoice('狗'));
      state = choicePickNext(state, const TickChoicePick(100));
      expect(state.wrongChoiceMs, gameWrongChoiceFeedbackMs - 100);
      expect(state.isLocked, isTrue);
    });

    test('推进到下一题会清掉逐题耗时与红框', () {
      var state = choicePickNext(start(), const PickChoice('狗'));
      state = choicePickNext(
        state,
        const TickChoicePick(gameWrongChoiceFeedbackMs),
      );
      state = choicePickNext(state, const PickChoice('猫'));
      state = choicePickNext(state, const AdvanceChoicePick());
      expect(state.current!.itemId, 2);
      expect(state.itemElapsedMs, 0);
      expect(state.wrongChoice, isNull);
      expect(state.wrongChoiceMs, 0);
      expect(state.solved, isFalse);
    });

    test('时间耗尽即结束本局，之后的点击不再生效', () {
      final state = choicePickNext(
        start(durationSeconds: 1),
        const TickChoicePick(1000),
      );
      expect(state.core.isFinished, isTrue);
      expect(state.current, isNull);
      final after = choicePickNext(state, const PickChoice('猫'));
      expect(after.core.records.solvedItemIds, isEmpty);
    });

    test('作答耗时会随 tick 累计，用于速度加减分', () {
      var state = start();
      state = choicePickNext(state, const TickChoicePick(500));
      expect(state.itemElapsedMs, 500);
      state = choicePickNext(state, const PickChoice('猫'));
      expect(state.core.records.durationsMs[1], 500);
    });
  });

  group('运行态', () {
    test('两个模式建出同一个选择题运行态', () {
      for (final mode in <GameMode>[
        GameMode.listeningPick,
        GameMode.meaningBlitz,
      ]) {
        final runtime = startGameRuntime(
          mode: mode,
          plan: gamePlanFor(mode, itemCount: 2),
          questions: twoMeaningQuestions(),
          random: () => 0,
        );
        expect(runtime, isA<ChoicePickRuntime>(), reason: mode.wire);
        expect(runtime.core.isPlaying, isTrue, reason: '开局即开始计时');
      }
    });

    test('动作与游戏不匹配时返回 null', () {
      final runtime = startGameRuntime(
        mode: GameMode.listeningPick,
        plan: gamePlanFor(GameMode.listeningPick, itemCount: 2),
        questions: <GameQuestion>[listeningQuestion()],
        random: () => 0,
      );
      expect(runtime.dispatch(const AdvanceWordBuilder()), isNull);
      expect(
        runtime.dispatch(const PickChoice('cat')),
        isA<ChoicePickRuntime>(),
      );
    });

    test('动作映射覆盖两个模式', () {
      for (final mode in <GameMode>[
        GameMode.listeningPick,
        GameMode.meaningBlitz,
      ]) {
        expect(startActionFor(mode), isA<StartChoicePick>(), reason: mode.wire);
        expect(tickActionFor(mode, 100), isA<TickChoicePick>());
        expect(advanceActionFor(mode), isA<AdvanceChoicePick>());
      }
    });

    test('答对后 awaitingAdvance 为真，推进后换题', () {
      var runtime = startGameRuntime(
        mode: GameMode.meaningBlitz,
        plan: gamePlanFor(GameMode.meaningBlitz, itemCount: 2),
        questions: twoMeaningQuestions(),
        random: () => 0,
      );
      expect(runtime.awaitingAdvance, isFalse);
      runtime = runtime.dispatch(const PickChoice('猫'))!;
      expect(runtime.awaitingAdvance, isTrue);
      runtime = runtime.dispatch(const AdvanceChoicePick())!;
      expect(runtime.awaitingAdvance, isFalse);
      expect(runtime.current!.itemId, 2);
    });
  });
}
