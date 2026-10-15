/// 计分函数的单元测试。
///
/// 这一层的价值在于「四个游戏 + 配对 + 音标共用同一套算式」这件事
/// 可以被断言：旧版 `games/completion.ts` 与 `matching/service.ts`
/// 各写一套权重，任何一处改动都不会影响另一处，因此没人能说清
/// 「小游戏 100 分 vs 配对 120 分」到底是不是有意的。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/scoring.dart';

void main() {
  group('scoreForAnswer', () {
    test('答错扣该模式的失误罚分，且不因模式不同而混淆', () {
      for (final mode in GameMode.values) {
        final rules = rulesFor(mode).score;
        expect(
          scoreForAnswer(
            isCorrect: false,
            comboCount: 0,
            elapsedMs: 0,
            mode: mode,
          ),
          -rules.mistakePenalty,
          reason: '${mode.wire} 的失误罚分应为 ${rules.mistakePenalty}',
        );
      }
    });

    test('首次答对只有基础分 + 快答奖励', () {
      final score = scoreForAnswer(
        isCorrect: true,
        comboCount: 1,
        elapsedMs: gameFastAnswerMs,
        mode: GameMode.whackAMole,
      );
      expect(score, gameBasePoints + gameFastAnswerBonus);
    });

    test('连击加成按步长累加，超过封顶后不再增加', () {
      // 取「不快也不慢」的耗时，让分数差异只来自连击。
      int scoreAt(int combo) => scoreForAnswer(
        isCorrect: true,
        comboCount: combo,
        elapsedMs: gameFastAnswerMs + 1,
        mode: GameMode.whackAMole,
      );
      expect(scoreAt(1), gameBasePoints);
      expect(scoreAt(2), gameBasePoints + gameComboStep);
      expect(scoreAt(3), gameBasePoints + 2 * gameComboStep);
      final capped = scoreAt(1 + gameComboCap);
      expect(scoreAt(1 + gameComboCap + 5), capped);
      expect(capped, gameBasePoints + gameComboCap * gameComboStep);
    });

    test('慢答扣速度分，快答加速度分，中间不加不减', () {
      int score(int elapsedMs) => scoreForAnswer(
        isCorrect: true,
        comboCount: 1,
        elapsedMs: elapsedMs,
        mode: GameMode.wordStack,
      );
      expect(score(0), gameBasePoints + gameFastAnswerBonus);
      expect(score(gameFastAnswerMs + 1), gameBasePoints);
      expect(score(gameSlowAnswerMs), gameBasePoints - gameSlowAnswerPenalty);
    });

    test('四个游戏共用一套基础权重，配对与音标各用自己的', () {
      const miniGames = <GameMode>[
        GameMode.wordBuilder,
        GameMode.whackAMole,
        GameMode.wordStack,
        GameMode.wordTetris,
      ];
      for (final mode in miniGames) {
        final rules = rulesFor(mode).score;
        expect(rules.basePoints, gameBasePoints);
        expect(rules.comboStep, gameComboStep);
        expect(rules.mistakePenalty, gameMistakePenalty);
      }
      expect(rulesFor(GameMode.match).score.basePoints, matchBasePoints);
      expect(rulesFor(GameMode.match).score.comboStep, matchComboStep);
      expect(
        rulesFor(GameMode.match).score.mistakePenalty,
        matchMistakePenalty,
      );
      expect(rulesFor(GameMode.phonetics).score.basePoints, phoneticBasePoints);
      expect(rulesFor(GameMode.phonetics).score.comboStep, phoneticComboStep);
      expect(
        rulesFor(GameMode.phonetics).score.mistakePenalty,
        phoneticMistakePenalty,
      );
    });
  });

  group('accuracyPercent', () {
    test('0 题返回 0（不能除零）', () {
      expect(accuracyPercent(correct: 0, total: 0), 0);
    });

    test('全对 100、全错 0', () {
      expect(accuracyPercent(correct: 7, total: 7), 100);
      expect(accuracyPercent(correct: 0, total: 7), 0);
    });

    test('四舍五入且越界值被夹紧', () {
      expect(accuracyPercent(correct: 1, total: 3), 33);
      expect(accuracyPercent(correct: 2, total: 3), 67);
      expect(accuracyPercent(correct: 9, total: 3), 100);
      expect(accuracyPercent(correct: -4, total: 3), 0);
    });
  });

  group('maxCombo', () {
    test('空列表返回 0', () => expect(maxCombo(<bool>[]), 0));
    test('全对等于长度', () {
      expect(maxCombo(<bool>[true, true, true]), 3);
    });
    test('全错返回 0', () {
      expect(maxCombo(<bool>[false, false]), 0);
    });
    test('取最长连续段而不是总和', () {
      expect(maxCombo(<bool>[true, false, true, true, true, false, true]), 3);
    });
  });

  group('finalScore 与评级', () {
    GameRoundSummary summary({
      int answerScore = 0,
      int elapsedMs = 0,
      int durationMs = 0,
    }) => GameRoundSummary(
      answerScore: answerScore,
      firstTryCorrect: 1,
      recovered: 0,
      missed: 0,
      mistakeCount: 0,
      maxCombo: 1,
      elapsedMs: elapsedMs,
      durationMs: durationMs,
    );

    test('配对把剩余时间换成分数并封顶', () {
      final score = finalScore(
        summary: summary(answerScore: 100, durationMs: 90000),
        mode: GameMode.match,
      );
      expect(score, 100 + matchRemainingTimeBonusCap);
    });

    test('四个小游戏不加剩余时间分', () {
      expect(
        finalScore(
          summary: summary(answerScore: 100, durationMs: 90000),
          mode: GameMode.whackAMole,
        ),
        100,
      );
    });

    test('罚分多于得分时结果夹到 0', () {
      expect(
        finalScore(
          summary: summary(answerScore: -50),
          mode: GameMode.wordStack,
        ),
        0,
      );
    });

    test('评级按得分占理论上限的比例给出', () {
      final max = maxScoreFor(GameMode.whackAMole);
      expect(max, greaterThan(0));
      expect(rankFor(score: max, mode: GameMode.whackAMole), GameRank.s);
      expect(rankFor(score: 0, mode: GameMode.whackAMole), GameRank.c);
      expect(
        rankFor(
          score: max * gameRankAPercent ~/ 100,
          mode: GameMode.whackAMole,
        ),
        GameRank.a,
      );
      expect(
        rankFor(
          score: max * gameRankBPercent ~/ 100,
          mode: GameMode.whackAMole,
        ),
        GameRank.b,
      );
    });

    test('理论上限随题量变化，题量取自模式规则', () {
      expect(
        maxScoreFor(GameMode.wordBuilder),
        wordBuilderItemCount *
                (gameBasePoints +
                    gameComboCap * gameComboStep +
                    gameFastAnswerBonus) +
            0,
      );
    });
  });
}
