/// 限时词汇配对的编排。
///
/// 对应旧版 `modules/matching/service.ts`。
///
/// **与旧版的差异（重要）**：旧版在 `matching/service.ts` 里**又写了一套
/// 计分权重**（`firstTryCorrect * 120 + recovered * 70 + min(600, 剩余ms/100)
/// + maxCombo * 15 - mistakeCount * 25`），与 `games/completion.ts` 的那套
/// 并存，这是 `docs/CLEAN_CODE_BASELINE.md` 点名的重复。本版两处都调用
/// `domain/games/scoring.dart` 的同一组函数，权重差异只体现在
/// `gameModeRules` 表里。
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
import 'package:lexiloop/domain/games/matching.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/review_service.dart';

/// 配对结算时写入 `user_answer` 的失败标记（旧版 `__MATCH_MISTAKE__`）。
const String matchMistakeAnswer = '__MATCH_MISTAKE__';

/// 配对编排入口。
class MatchingService {
  /// 以学习 DAO、作答服务与游戏 DAO 构造。
  new(this._study, this._review, this._dao);

  final StudyDao _study;
  final ReviewService _review;
  final GameDao _dao;

  /// 开始一局配对。
  ///
  /// [pairCount] 与 [durationSeconds] 会按旧版边界夹取
  /// （4–8 对、30–180 秒），非法配置不会让会话以荒谬的时长开局。
  Future<GameSession> start({
    required int pairCount,
    required int durationSeconds,
    required int now,
    double Function()? random,
  }) async {
    final pairs = _clamp(
      pairCount,
      matchingMinimumPairCount,
      matchingMaximumPairCount,
    );
    final seconds = _clamp(
      durationSeconds,
      matchingMinimumDurationSeconds,
      matchingMaximumDurationSeconds,
    );
    await _dao.closeOpenSessions(
      sourceTypePattern: GameMode.match.sourceType,
      now: now,
    );

    final candidates = await _dao.loadCandidates(
      now: now,
      limit: pairs,
      excludeWordsInActiveSessions: true,
    );
    if (candidates.length < matchingMinimumPairCount) {
      throw const ConflictError(AppErrorCode.notEnoughMatchingWords);
    }

    final sessionId = await _study.createSession(
      mode: StudyMode.wrongWords,
      sourceType: GameMode.match.sourceType,
      items: <StudySessionItemDraft>[
        for (final candidate in candidates)
          StudySessionItemDraft(
            wordId: candidate.id,
            taskType: _taskTypeFor(candidate.priority),
            questionType: QuestionType.enToZhChoice,
          ),
      ],
      now: now,
    );
    final itemIds = await _dao.sessionItemIds(sessionId);
    return GameSession(
      sessionId: sessionId,
      plan: gamePlanFor(
        GameMode.match,
        itemCount: candidates.length,
        durationSeconds: seconds,
      ),
      questions: <GameQuestion>[
        for (final candidate in candidates)
          if (itemIds[candidate.id] case final itemId?)
            GameQuestion(
              itemId: itemId,
              wordId: candidate.id,
              word: GameWord(
                term: candidate.term,
                definition: candidate.definition,
              ),
              choices: const GameChoices(options: <String>[]),
              priority: candidate.priority,
            ),
      ],
    );
  }

  /// 结算一局配对。
  Future<GameResult> complete({
    required GameSession session,
    required MatchBoardState state,
    required int now,
  }) async {
    final summary = state.core.summary;
    final pairCount = session.questions.length;
    final average = pairCount <= 0 ? 0 : summary.elapsedMs ~/ pairCount;
    final answers = state.core.answerRecords(
      session.questions,
      fallbackDurationMs: average,
    );
    final inputs = <AnswerInput>[
      for (final answer in answers)
        AnswerInput(
          clientAnswerId: 'match-${session.sessionId}-${answer.itemId}',
          wordId: answer.wordId,
          rating: answer.solved && !answer.hadMistake
              ? ReviewRating.good
              : ReviewRating.again,
          questionType: QuestionType.enToZhChoice,
          studySessionId: session.sessionId,
          studySessionItemId: answer.itemId,
          userAnswer: _userAnswer(session, answer),
          durationMs: answer.durationMs,
        ),
    ];
    if (inputs.isNotEmpty) {
      await _review.processAnswers(inputs, now: now);
    }

    final score = finalScore(summary: summary, mode: GameMode.match);
    await _dao.saveHighScore(
      mode: GameMode.match,
      score: score,
      maxCombo: summary.maxCombo,
      accuracy: summary.accuracy,
      elapsedMs: summary.elapsedMs,
      now: now,
    );
    return GameResult(
      mode: GameMode.match,
      score: score,
      summary: summary,
      rank: rankFor(score: score, mode: GameMode.match),
      leaderboard: await loadLeaderboard(
        dao: _dao,
        mode: GameMode.match,
        score: score,
      ),
    );
  }

  /// 配对题的期望答案是**中文释义**（题型是 `EN_TO_ZH_CHOICE`），
  /// 与旧版 `correctAnswer(row)` 的取值一致。
  String _userAnswer(GameSession session, GameAnswerRecord answer) {
    if (!answer.solved || answer.hadMistake) return matchMistakeAnswer;
    for (final question in session.questions) {
      if (question.itemId == answer.itemId) return question.word.definition;
    }
    return matchMistakeAnswer;
  }

  /// 任务类型（对应旧版 `classifyDueAsReview: true` 的分支）。
  StudyTaskType _taskTypeFor(GamePriority priority) => switch (priority) {
    GamePriority.wrong => StudyTaskType.wrong,
    GamePriority.due => StudyTaskType.review,
    _ => StudyTaskType.newWord,
  };

  int _clamp(int value, int minimum, int maximum) =>
      math.max(minimum, math.min(maximum, value));
}
