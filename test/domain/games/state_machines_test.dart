/// 四个小游戏与配对牌面的状态机测试。
///
/// **这是本任务的核心验收点**：旧版把规则写进 React 组件，只能靠点界面
/// 验证「锤错会不会清零连击」「时间到会不会结束」；这里每个规则都有一条
/// 断言，且随机源注入后结果完全确定。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/domain/games/matching.dart';
import 'package:lexiloop/domain/games/whack_a_mole.dart';
import 'package:lexiloop/domain/games/word_builder.dart';
import 'package:lexiloop/domain/games/word_stack.dart';
import 'package:lexiloop/domain/games/word_tetris.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

import 'random_source.dart';

/// 造一道题；[choices] 缺省时正确项排第一。
GameQuestion buildQuestion({
  required int itemId,
  required String term,
  required String definition,
  List<String>? choices,
  GamePriority priority = GamePriority.normal,
}) {
  return GameQuestion(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(
      term: term,
      definition: definition,
      letters: buildLetterTiles(term, random: constantRandom()),
    ),
    choices: GameChoices(
      options: choices ?? <String>[term, 'alpha', 'bravo', 'charlie'],
    ),
    priority: priority,
  );
}

/// 两道题的固定题面。
List<GameQuestion> twoQuestions() => <GameQuestion>[
  buildQuestion(itemId: 1, term: 'cat', definition: '猫'),
  buildQuestion(itemId: 2, term: 'dog', definition: '狗'),
];

void main() {
  group('词汇地鼠', () {
    WhackAMoleState start({int itemCount = 2, int durationSeconds = 60}) {
      final state = startWhackAMole(
        plan: gamePlanFor(
          GameMode.whackAMole,
          itemCount: itemCount,
          durationSeconds: durationSeconds,
        ),
        questions: twoQuestions(),
        random: constantRandom(),
      );
      return whackAMoleNext(state, const StartWhackAMole());
    }

    test('初始状态是 ready，开始后进入 playing', () {
      final ready = startWhackAMole(
        plan: gamePlanFor(GameMode.whackAMole),
        questions: twoQuestions(),
        random: constantRandom(),
      );
      expect(ready.core.progress.phase, GamePhase.ready);
      expect(ready.core.isPlaying, isFalse);
      expect(ready.current, isNotNull);
      expect(
        whackAMoleNext(ready, const StartWhackAMole()).core.isPlaying,
        isTrue,
      );
    });

    test('锤中正确词加分并递增连击', () {
      final state = whackAMoleNext(start(), const WhackMole('cat'));
      expect(state.solved, isTrue);
      expect(state.core.tally.combo, 1);
      expect(
        state.core.tally.score,
        gameBasePoints + gameFastAnswerBonus,
        reason: '零耗时属于快答',
      );
      expect(state.core.outcomeFor(1), GameOutcome.firstTry);
    });

    test('锤错记一次失误并清零连击，但可以继续锤', () {
      var state = whackAMoleNext(start(), const WhackMole('cat'));
      state = whackAMoleNext(state, const AdvanceWhackAMole());
      state = whackAMoleNext(state, const WhackMole('alpha'));
      expect(state.core.tally.mistakeCount, 1);
      expect(state.core.tally.combo, 0);
      expect(state.whackedWrong, contains('alpha'));
      expect(state.solved, isFalse);
      expect(state.core.records.hasMistake(2), isTrue);
      final recovered = whackAMoleNext(state, const WhackMole('dog'));
      expect(recovered.solved, isTrue);
      expect(recovered.core.outcomeFor(2), GameOutcome.recovered);
    });

    test('地鼠全部缩回时本题判为未完成，但不算「失误次数」', () {
      final state = whackAMoleNext(
        start(),
        const TickWhackAMole(whackAMoleStayMs + 10000),
      );
      expect(state.failed, isTrue);
      expect(state.core.outcomeFor(1), GameOutcome.missed);
      expect(state.core.tally.mistakeCount, 0, reason: '与旧版一致：超时不计失误');
      expect(state.core.tally.combo, 0);
    });

    test('地鼠按间隔依次冒头', () {
      final state = whackAMoleNext(
        start(),
        const TickWhackAMole(whackAMolePopDelayMs + whackAMoleStaggerMs),
      );
      expect(state.isMoleUp(0), isTrue);
      expect(state.isMoleUp(1), isTrue);
      expect(state.isMoleUp(2), isFalse);
    });

    test('时间耗尽结束本局，结束态不可再推进', () {
      final state = whackAMoleNext(start(), const TickWhackAMole(60000));
      expect(state.core.isFinished, isTrue);
      final frozen = whackAMoleNext(state, const WhackMole('cat'));
      expect(frozen.solved, isFalse);
      expect(frozen.core.tally.score, state.core.tally.score);
    });

    test('逐题作答记录覆盖未作答的题目', () {
      final state = whackAMoleNext(start(), const TickWhackAMole(60000));
      final records = state.core.answerRecords(state.questions);
      expect(records.length, 2);
      expect(records.every((item) => !item.solved), isTrue);
      expect(records.every((item) => item.hadMistake), isTrue);
    });
  });

  group('单词拼图', () {
    WordBuilderState start({int durationSeconds = 90}) {
      final state = startWordBuilder(
        plan: gamePlanFor(
          GameMode.wordBuilder,
          itemCount: 2,
          durationSeconds: durationSeconds,
        ),
        questions: twoQuestions(),
      );
      return wordBuilderNext(state, const StartWordBuilder());
    }

    WordBuilderState selectAll(WordBuilderState state, List<String> ids) {
      var next = state;
      for (final id in ids) {
        next = wordBuilderNext(next, SelectLetter(id));
      }
      return next;
    }

    test('字母必须全部用完才能提交', () {
      final partial = wordBuilderNext(start(), const SelectLetter('0-c'));
      expect(partial.isComplete, isFalse);
      final submitted = wordBuilderNext(partial, const SubmitWord());
      expect(submitted.core.records.isSolved(1), isFalse);
      expect(submitted.core.tally.mistakeCount, 0);
    });

    test('拼对即解决', () {
      final solved = wordBuilderNext(
        selectAll(start(), <String>['0-c', '1-a', '2-t']),
        const SubmitWord(),
      );
      expect(solved.answer, 'cat');
      expect(solved.core.records.isSolved(1), isTrue);
      expect(solved.core.outcomeFor(1), GameOutcome.firstTry);
    });

    test('拼错清空字母并记一次失误', () {
      // 顺序颠倒成 `tac`：字母都对，但拼出来的不是这个词。
      final built = selectAll(start(), <String>['2-t', '1-a', '0-c']);
      expect(built.answer, 'tac');
      final bad = wordBuilderNext(built, const SubmitWord());
      expect(bad.core.tally.mistakeCount, 1);
      expect(bad.selectedIds, isEmpty);
      expect(bad.wrong, isTrue);
      expect(bad.core.records.isSolved(1), isFalse);
    });

    test('「不认识」揭示答案、暂停计时、记一次失误', () {
      var state = wordBuilderNext(start(), const RevealWord());
      expect(state.revealed, isTrue);
      expect(state.core.tally.mistakeCount, 1);
      final paused = state.itemElapsedMs;
      state = wordBuilderNext(state, const TickWordBuilder(5000));
      expect(state.itemElapsedMs, paused, reason: '揭示答案期间不计时');
      state = wordBuilderNext(state, const ConfirmRevealed());
      expect(state.revealed, isFalse);
      expect(state.core.outcomeFor(1), GameOutcome.missed);
    });

    test('选中的字母块不可重复选入', () {
      var state = selectAll(start(), <String>['0-c', '0-c']);
      expect(state.selectedIds, <String>['0-c']);
      state = wordBuilderNext(state, const DeselectLetter('0-c'));
      expect(state.selectedIds, isEmpty);
      state = wordBuilderNext(
        wordBuilderNext(state, const SelectLetter('0-c')),
        const ClearLetters(),
      );
      expect(state.selectedIds, isEmpty);
    });

    test('时间耗尽结束本局', () {
      final state = wordBuilderNext(start(), const TickWordBuilder(90000));
      expect(state.core.isFinished, isTrue);
    });
  });

  group('单词堆堆乐', () {
    WordStackState start() {
      final state = startWordStack(
        plan: gamePlanFor(GameMode.wordStack, itemCount: 2),
        questions: twoQuestions(),
      );
      return wordStackNext(state, const StartWordStack());
    }

    test('点错掉落并进入冷却，冷却期内不可再点', () {
      var state = wordStackNext(start(), const TapStackBlock('alpha'));
      expect(state.isDropped('alpha'), isTrue);
      expect(state.core.tally.mistakeCount, 1);
      state = wordStackNext(state, const TapStackBlock('alpha'));
      expect(state.core.tally.mistakeCount, 1, reason: '冷却期内重复点击不计数');
      state = wordStackNext(
        state,
        const TickWordStack(wordStackBlockCooldownMs),
      );
      expect(state.isDropped('alpha'), isFalse);
    });

    test('点对堆起塔层并记为纠正完成', () {
      var state = wordStackNext(start(), const TapStackBlock('alpha'));
      state = wordStackNext(state, const TapStackBlock('cat'));
      expect(state.popped, isTrue);
      expect(state.core.outcomeFor(1), GameOutcome.recovered);
      expect(state.tower, <String>['cat']);
      state = wordStackNext(state, const AdvanceWordStack());
      expect(state.popped, isFalse);
      expect(state.current!.itemId, 2);
    });

    test('时间耗尽结束本局，结束态不可再推进', () {
      final state = wordStackNext(
        start(),
        const TickWordStack(wordStackItemCount * 100000),
      );
      expect(state.core.isFinished, isTrue);
      final frozen = wordStackNext(state, const TapStackBlock('cat'));
      expect(frozen.popped, isFalse);
      expect(frozen.core.records.isSolved(1), isFalse);
    });
  });

  group('词汇俄罗斯方块', () {
    WordTetrisState start({int itemCount = 2, List<GameQuestion>? questions}) {
      final state = startWordTetris(
        plan: gamePlanFor(
          GameMode.wordTetris,
          itemCount: itemCount,
          durationSeconds: 75,
        ),
        questions: questions ?? twoQuestions(),
        random: constantRandom(),
      );
      return wordTetrisNext(state, const StartWordTetris());
    }

    test('点错记失误并抖动，点对消掉一层', () {
      var state = wordTetrisNext(start(), const TapTetrisBlock('alpha'));
      expect(state.core.tally.mistakeCount, 1);
      expect(state.shakingWord, 'alpha');
      state = wordTetrisNext(state, const ClearTetrisShake());
      expect(state.shakingWord, isNull);
      state = wordTetrisNext(state, const TapTetrisBlock('cat'));
      expect(state.core.records.isSolved(1), isTrue);
      expect(state.danger, 0);
      expect(state.core.tally.combo, 1);
    });

    test('正确方块落地即判本题未完成并进入下一题', () {
      var state = wordTetrisNext(start(), const TickWordTetris(100));
      expect(state.danger, 0, reason: '尚未落地');
      state = wordTetrisNext(state, const TickWordTetris(5000));
      expect(state.danger, greaterThan(0));
      expect(state.core.outcomeFor(1), GameOutcome.missed);
    });

    test('堆满即结束本局', () {
      final questions = <GameQuestion>[
        buildQuestion(
          itemId: 1,
          term: 'cat',
          definition: '猫',
          choices: <String>['alpha', 'bravo', 'charlie', 'cat'],
        ),
        buildQuestion(
          itemId: 2,
          term: 'dog',
          definition: '狗',
          choices: <String>['alpha', 'bravo', 'charlie', 'dog'],
        ),
      ];
      var state = start(questions: questions);
      for (var index = 0; index < 200 && !state.core.isFinished; index += 1) {
        state = wordTetrisNext(state, const TickWordTetris(100));
      }
      expect(state.core.isFinished, isTrue);
      expect(state.danger, wordTetrisDangerCap);
    });

    test('方块位置随剩余时间单调推进', () {
      final state = start();
      final before = state.board.blocks.first.progress;
      final after = wordTetrisNext(
        state,
        const TickWordTetris(100),
      ).board.blocks.first.progress;
      expect(after, greaterThan(before));
    });

    test('时间耗尽结束本局', () {
      final state = wordTetrisNext(start(), const TickWordTetris(75000));
      expect(state.core.isFinished, isTrue);
    });
  });

  group('配对牌面', () {
    List<GameQuestion> fourPairs() => <GameQuestion>[
      for (final entry in <List<String>>[
        <String>['cat', '猫'],
        <String>['dog', '狗'],
        <String>['pig', '猪'],
        <String>['cow', '牛'],
      ])
        buildQuestion(
          itemId: entry[0].length,
          term: entry[0],
          definition: entry[1],
          choices: const <String>[],
        ),
    ];

    MatchBoardState start() {
      final board = startMatchingBoard(
        plan: gamePlanFor(GameMode.match, itemCount: 4),
        pairs: <GameQuestion>[
          buildQuestion(itemId: 1, term: 'cat', definition: '猫'),
          buildQuestion(itemId: 2, term: 'dog', definition: '狗'),
          buildQuestion(itemId: 3, term: 'pig', definition: '猪'),
          buildQuestion(itemId: 4, term: 'cow', definition: '牛'),
        ],
        random: constantRandom(),
      );
      return matchBoardNext(board, const StartMatch());
    }

    test('四对词条的题面构造不受长度影响', () {
      expect(fourPairs().length, 4);
    });

    test('同一列内再点一张只切换选择，点同一张则取消', () {
      var board = matchBoardNext(
        start(),
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      expect(board.feedback.selected!.itemId, 1);
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.word, itemId: 2),
      );
      expect(board.feedback.selected!.itemId, 2);
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.word, itemId: 2),
      );
      expect(board.feedback.selected, isNull);
    });

    test('错配记一次失误、两张牌都标记、期间锁定牌面', () {
      var board = matchBoardNext(
        start(),
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.definition, itemId: 2),
      );
      expect(board.core.tally.mistakeCount, 1);
      expect(board.feedback.isLocked, isTrue);
      expect(board.core.records.hasMistake(1), isTrue);
      expect(board.core.records.hasMistake(2), isTrue);
      final locked = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.word, itemId: 3),
      );
      expect(locked.matchedItemIds, isEmpty);
      expect(locked.feedback.selected!.itemId, 1, reason: '锁定期间选择不变');
      board = matchBoardNext(board, const ClearMatchFlash());
      expect(board.feedback.isLocked, isFalse);
    });

    test('配对成功后该词条记为纠正完成，全部配对即结束', () {
      var board = matchBoardNext(
        start(),
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.definition, itemId: 2),
      );
      board = matchBoardNext(board, const ClearMatchFlash());
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.definition, itemId: 1),
      );
      expect(board.matchedItemIds, contains(1));
      expect(board.core.outcomeFor(1), GameOutcome.recovered);

      for (final id in <int>[2, 3, 4]) {
        board = matchBoardNext(
          board,
          TapMatchCard(side: MatchSide.word, itemId: id),
        );
        board = matchBoardNext(
          board,
          TapMatchCard(side: MatchSide.definition, itemId: id),
        );
      }
      expect(board.isComplete, isTrue);
      expect(board.core.isFinished, isTrue);
      // 错配时两张牌都被标记为「曾失误」（与旧版一致），
      // 因此第 2 对即便后来干净地配对成功也只算「纠正完成」。
      expect(board.core.summary.firstTryCorrect, 2);
      expect(board.core.summary.recovered, 2);
    });

    test('一次配对成功记「一次配对」，连击递增', () {
      var board = matchBoardNext(
        start(),
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      board = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.definition, itemId: 1),
      );
      expect(board.core.outcomeFor(1), GameOutcome.firstTry);
      expect(board.core.tally.combo, 1);
      expect(
        board.core.summary.answerScore,
        matchBasePoints + gameFastAnswerBonus,
      );
    });

    test('时间耗尽结束本局', () {
      final board = matchBoardNext(start(), const TickMatch(60000));
      expect(board.core.isFinished, isTrue);
      final frozen = matchBoardNext(
        board,
        const TapMatchCard(side: MatchSide.word, itemId: 1),
      );
      expect(frozen.matchedItemIds, isEmpty);
    });
  });

  group('运行态联合类型', () {
    test('动作与游戏不匹配时返回 null，匹配时返回新状态', () {
      final runtime = startGameRuntime(
        mode: GameMode.whackAMole,
        plan: gamePlanFor(GameMode.whackAMole, itemCount: 2),
        questions: twoQuestions(),
        random: constantRandom(),
      );
      expect(runtime, isA<WhackAMoleRuntime>());
      expect(runtime.core.isPlaying, isTrue, reason: '开局即开始计时');
      expect(runtime.dispatch(const AdvanceWordBuilder()), isNull);
      expect(
        runtime.dispatch(const WhackMole('cat')),
        isA<WhackAMoleRuntime>(),
      );
    });

    test('四个模式各自建出对应的运行态', () {
      expect(
        startGameRuntime(
          mode: GameMode.wordBuilder,
          plan: gamePlanFor(GameMode.wordBuilder, itemCount: 2),
          questions: twoQuestions(),
          random: constantRandom(),
        ),
        isA<WordBuilderRuntime>(),
      );
      expect(
        startGameRuntime(
          mode: GameMode.wordStack,
          plan: gamePlanFor(GameMode.wordStack, itemCount: 2),
          questions: twoQuestions(),
          random: constantRandom(),
        ),
        isA<WordStackRuntime>(),
      );
      expect(
        startGameRuntime(
          mode: GameMode.wordTetris,
          plan: gamePlanFor(GameMode.wordTetris, itemCount: 2),
          questions: twoQuestions(),
          random: constantRandom(),
        ),
        isA<WordTetrisRuntime>(),
      );
    });

    test('答题后 awaitingAdvance 为真，推进后为假', () {
      var runtime = startGameRuntime(
        mode: GameMode.wordStack,
        plan: gamePlanFor(GameMode.wordStack, itemCount: 2),
        questions: twoQuestions(),
        random: constantRandom(),
      );
      expect(runtime.awaitingAdvance, isFalse);
      runtime = runtime.dispatch(const TapStackBlock('cat'))!;
      expect(runtime.awaitingAdvance, isTrue);
      runtime = runtime.dispatch(const AdvanceWordStack())!;
      expect(runtime.awaitingAdvance, isFalse);
      expect(runtime.current!.itemId, 2);
    });
  });
}
