/// 四个小游戏的编排。
///
/// 对应旧版 `modules/games/service.ts`（开局）与
/// `modules/games/completion.ts`（结算）。
///
/// **职责边界**：
/// - 规则与计分在 `domain/games/`（纯函数，可单测）；
/// - 候选查询与高分榜在 `GameDao`；
/// - 本层只负责「查候选 → 造题 → 落会话 → 结算 → 记分」这条流水线。
///
/// **结算必须走 [ReviewService.processAnswers]**：它已实现「整批一个事务」
/// 与按 `client_answer_id` 的幂等。旧版小游戏另写了一条结算路径，
/// 结果是「玩到一半失败会留下半个分数」；这里不再重复实现。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/question_payload.dart';
import 'package:lexiloop/services/review_service.dart';

/// 小游戏结算时写入 `user_answer` 的失败标记。
///
/// 与旧版 `failureAnswer: "__GAME_MISTAKE__"` 一致：复习日志里能一眼看出
/// 这次作答不是用户拼出来的，而是游戏判负。
const String gameMistakeAnswer = '__GAME_MISTAKE__';

/// 一局的会话数据。
class GameSession {
  /// 以各字段构造。
  const new({
    required this.sessionId,
    required this.plan,
    required this.questions,
  });

  /// 学习会话 ID。
  final int sessionId;

  /// 本局的计划（模式、题量、时限）。
  final GamePlan plan;

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 模式。
  GameMode get mode => plan.mode;
}

/// 排行榜摘要（旧版 `LeaderboardSummary`）。
class GameLeaderboard {
  /// 以各字段构造。
  const new({
    required this.rank,
    required this.best,
    required this.top,
    required this.isNewBest,
  });

  /// 本轮名次（1 起）。
  final int rank;

  /// 历史最高分。
  final int best;

  /// 前 [leaderboardLimit] 名。
  final List<GameHighScore> top;

  /// 本轮是否刷新了纪录。
  final bool isNewBest;
}

/// 一局的结算结果。
class GameResult {
  /// 以各字段构造。
  const new({
    required this.mode,
    required this.score,
    required this.summary,
    required this.rank,
    required this.leaderboard,
  });

  /// 模式。
  final GameMode mode;

  /// 最终得分。
  final int score;

  /// 作答汇总。
  final GameRoundSummary summary;

  /// 评级（旧版没有评级，本版按得分比例给出）。
  final GameRank rank;

  /// 排行榜摘要。
  final GameLeaderboard leaderboard;
}

/// 读取某模式的高分榜摘要。
///
/// 三个业务线（小游戏 / 配对 / 音标）共用同一份实现——旧版
/// `games/completion.ts`、`matching/service.ts`、`phonetics/service.ts`
/// 各自调用了一次 `recordScore`，但计分与榜单读取的边界并不一致；
/// 收敛到一处后，「什么时候写榜、什么时候读榜」只有一种顺序。
Future<GameLeaderboard> loadLeaderboard({
  required GameDao dao,
  required GameMode mode,
  required int score,
}) async {
  final rank = await dao.rankOf(mode: mode, score: score);
  final best = await dao.bestScore(mode);
  final top = await dao.topScores(mode: mode, limit: leaderboardLimit);
  return GameLeaderboard(
    rank: rank,
    best: best,
    top: top,
    isNewBest: rank == 1,
  );
}

/// 小游戏编排入口。
class GameService {
  /// 以数据库、学习 DAO、作答服务与游戏 DAO 构造。
  new(this._study, this._review, this._dao);

  final StudyDao _study;
  final ReviewService _review;
  final GameDao _dao;

  /// 开始一局小游戏。
  ///
  /// [random] 可注入，便于确定性测试；不传时用系统随机源。
  Future<GameSession> start({
    required GameMode mode,
    required int now,
    double Function()? random,
  }) async {
    final source = mode.sourceType;
    await _dao.closeOpenSessions(sourceTypePattern: source, now: now);

    final rules = rulesFor(mode);
    final candidates = await _dao.loadCandidates(
      now: now,
      limit: gameCandidateQueryLimit,
      wordsOnly: mode == GameMode.wordBuilder,
    );
    if (candidates.length < gameMinimumItemCount) {
      throw const ConflictError(AppErrorCode.notEnoughGameWords);
    }

    final picked = candidates.take(rules.session.itemCount).toList();
    final drafts = <StudySessionItemDraft>[
      for (final candidate in picked)
        StudySessionItemDraft(
          wordId: candidate.id,
          taskType: rules.session.taskType,
          questionType: rules.session.questionType,
        ),
    ];
    final sessionId = await _study.createSession(
      mode: rules.session.sessionType,
      sourceType: source,
      items: drafts,
      now: now,
    );
    final itemIds = await _dao.sessionItemIds(sessionId);
    final plan = gamePlanFor(mode, itemCount: picked.length);
    return GameSession(
      sessionId: sessionId,
      plan: plan,
      questions: _buildQuestions(
        mode: mode,
        candidates: picked,
        itemIds: itemIds,
        random: random ?? math.Random().nextDouble,
      ),
    );
  }

  /// 结算一局小游戏。
  ///
  /// [answers] 与 [summary] 都来自状态机（`GameCoreState.answerRecords`
  /// 与 `GameCoreState.summary`），本层不重新判定正误。
  Future<GameResult> complete({
    required GameSession session,
    required GameRoundSummary summary,
    required List<GameAnswerRecord> answers,
    required int now,
  }) async {
    final mode = session.mode;
    final rules = rulesFor(mode);
    final inputs = <AnswerInput>[
      for (final answer in answers)
        AnswerInput(
          clientAnswerId:
              'game-${mode.wire}-${session.sessionId}-${answer.itemId}',
          wordId: answer.wordId,
          rating: answer.solved && !answer.hadMistake
              ? ReviewRating.good
              : ReviewRating.again,
          questionType: rules.session.questionType,
          studySessionId: session.sessionId,
          studySessionItemId: answer.itemId,
          userAnswer: _userAnswer(session, answer),
          durationMs: answer.durationMs,
        ),
    ];
    if (inputs.isNotEmpty) {
      await _review.processAnswers(inputs, now: now);
    }

    final score = finalScore(summary: summary, mode: mode);
    await _dao.saveHighScore(
      mode: mode,
      score: score,
      maxCombo: summary.maxCombo,
      accuracy: summary.accuracy,
      elapsedMs: summary.elapsedMs,
      now: now,
    );
    return GameResult(
      mode: mode,
      score: score,
      summary: summary,
      rank: rankFor(score: score, mode: mode),
      leaderboard: await loadLeaderboard(dao: _dao, mode: mode, score: score),
    );
  }

  /// 记录到复习日志里的作答原文。
  ///
  /// 中译英类题目答对时写正确词条（让日志与期望答案一致），
  /// 否则写失败标记——把「没拼出来」写成空串会让复盘时无法区分
  /// 「答错」与「没作答」。
  String _userAnswer(GameSession session, GameAnswerRecord answer) {
    if (!answer.solved || answer.hadMistake) return gameMistakeAnswer;
    for (final question in session.questions) {
      if (question.itemId == answer.itemId) return question.word.term;
    }
    return gameMistakeAnswer;
  }

  /// 按模式造题。
  ///
  /// 中译英选择题的选项池是「本局全部候选词条」——与旧版
  /// `createChoicePool(candidate.term, terms, CHOICE_COUNT)` 一致。
  /// 单词拼图额外构造字母块，并保证打乱后不恰好等于原词。
  List<GameQuestion> _buildQuestions({
    required GameMode mode,
    required List<GameCandidate> candidates,
    required Map<int, int> itemIds,
    required double Function() random,
  }) {
    final terms = <String>[for (final candidate in candidates) candidate.term];
    final result = <GameQuestion>[];
    for (final candidate in candidates) {
      final itemId = itemIds[candidate.id];
      if (itemId == null) continue;
      result.add(
        GameQuestion(
          itemId: itemId,
          wordId: candidate.id,
          word: GameWord(
            term: candidate.term,
            definition: candidate.definition,
            letters: mode == GameMode.wordBuilder
                ? buildLetterTiles(candidate.term, random: random)
                : const <LetterTile>[],
          ),
          choices: GameChoices(
            options: mode == GameMode.wordBuilder
                ? const <String>[]
                : createChoicePool(
                    correct: candidate.term,
                    pool: terms,
                    size: gameChoiceCount,
                    random: random,
                  ),
          ),
          priority: candidate.priority,
        ),
      );
    }
    return result;
  }
}
