/// 音标辨音训练的编排。
///
/// 对应旧版 `modules/phonetics/service.ts`（开局与结算）与
/// `modules/phonetics/selection.ts`（选题）。
///
/// **音标训练不写 `review_logs`**——这是一条有意的设计决定，理由见
/// [PhoneticService.complete] 的文档。旧版的实际行为是**会写**，
/// 见类文档末尾的对照说明。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/domain/phonetics/pronunciation.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';
import 'package:lexiloop/services/game_service.dart';

/// 一个通过口音与目录校验的音标训练候选。
class _PhoneticPick {
  const new({required this.candidate, required this.phonetic});

  final GameCandidate candidate;
  final String phonetic;
}

/// 一局音标训练的会话数据。
class PhoneticSession {
  /// 以各字段构造。
  const new({
    required this.sessionId,
    required this.plan,
    required this.questions,
    required this.accent,
  });

  /// 学习会话 ID。
  final int sessionId;

  /// 本局的计划。
  final GamePlan plan;

  /// 全部题目。
  final List<PhoneticQuestion> questions;

  /// 本轮口音。
  final Accent accent;
}

/// 音标训练编排入口。
///
/// **旧版行为对照**：旧版 `phonetics/service.ts` 的 `completePhoneticGame`
/// 调用 `completePracticeSession`，后者内部会
/// `processReviewAnswersInTransaction`，因此**旧版确实写 `review_logs`**，
/// 并且把那些词条的 FSRS 一起推进了。本版不写，理由有三：
/// 1. 音标训练练的是「音素对立」，不是「这个词你记住了没有」，
///    推进词条 FSRS 会把两件事混成一个记忆强度；
/// 2. 旧版的会话来源是 `GAME_PHONETICS`，正好命中
///    `ReviewService._isExcludedSource` 的 `GAME_` 前缀而**跳过自适应插题**；
///    本版按规格改用 `PHONETIC_TRAINING`，若仍走 `processAnswers`，
///    答错会往音标会话里插入复习题，而 `review_service.dart` 不在本次改动范围内；
/// 3. 不写日志就必须自己收尾会话，这一条由
///    [GameDao.completePhoneticSession] 显式承担（逐题状态 + 计数 + 时长）。
class PhoneticService {
  /// 以学习 DAO 与游戏 DAO 构造。
  new(this._study, this._dao);

  final StudyDao _study;
  final GameDao _dao;

  /// 开始一局音标训练。
  Future<PhoneticSession> start({
    required Accent accent,
    required int now,
    double Function()? random,
  }) async {
    await _dao.closeOpenSessions(
      sourceTypePattern: phoneticTrainingSourceType,
      now: now,
    );
    final picks = await _loadPicks(accent: accent, now: now);
    if (picks.length < phoneticMinimumItemCount) {
      throw const ConflictError(AppErrorCode.notEnoughPhoneticWords);
    }

    final sessionId = await _study.createSession(
      mode: StudyMode.listening,
      sourceType: phoneticTrainingSourceType,
      items: <StudySessionItemDraft>[
        for (final pick in picks)
          StudySessionItemDraft(
            wordId: pick.candidate.id,
            taskType: StudyTaskType.listening,
            questionType: QuestionType.listeningSpelling,
          ),
      ],
      now: now,
    );
    final itemIds = await _dao.sessionItemIds(sessionId);
    final sources = <PhoneticSource>[
      for (final pick in picks)
        if (itemIds[pick.candidate.id] case final itemId?)
          PhoneticSource(
            itemId: itemId,
            wordId: pick.candidate.id,
            word: GameWord(
              term: pick.candidate.term,
              definition: pick.candidate.definition,
            ),
            phonetic: pick.phonetic,
            priority: pick.candidate.priority,
          ),
    ];
    final questions = buildPhoneticQuestions(
      sources: sources,
      count: phoneticItemCount,
      random: random ?? math.Random().nextDouble,
    );
    return PhoneticSession(
      sessionId: sessionId,
      plan: gamePlanFor(GameMode.phonetics, itemCount: questions.length),
      questions: questions,
      accent: accent,
    );
  }

  /// 结算一局音标训练。
  ///
  /// 只写 `game_high_scores` 与 `study_sessions`，**不写 `review_logs`**
  /// （见类文档）。
  Future<GameResult> complete({
    required PhoneticSession session,
    required PhoneticQuizState state,
    required int now,
  }) async {
    final summary = state.core.summary;
    final answers = phoneticAnswerRecords(state);
    await _dao.completePhoneticSession(
      sessionId: session.sessionId,
      answers: answers,
      answeredItemIds: state.core.records.durationsMs.keys.toSet(),
      elapsedMs: summary.elapsedMs,
      now: now,
    );
    final score = finalScore(summary: summary, mode: GameMode.phonetics);
    await _dao.saveHighScore(
      mode: GameMode.phonetics,
      score: score,
      maxCombo: summary.maxCombo,
      accuracy: summary.accuracy,
      elapsedMs: summary.elapsedMs,
      now: now,
    );
    return GameResult(
      mode: GameMode.phonetics,
      score: score,
      summary: summary,
      rank: rankFor(score: score, mode: GameMode.phonetics),
      leaderboard: await loadLeaderboard(
        dao: _dao,
        mode: GameMode.phonetics,
        score: score,
      ),
    );
  }

  /// 取出「有目标口音音标、且音标能归到目录条目」的候选。
  ///
  /// 三层过滤缺一不可：没有该口音的音标就没法出题；音标归不到目录条目
  /// 就没有解析可看；音标重复会让同一道题的选项里出现两个一样的音标。
  Future<List<_PhoneticPick>> _loadPicks({
    required Accent accent,
    required int now,
  }) async {
    final candidates = await _dao.loadCandidates(
      now: now,
      limit: phoneticCandidatePoolSize,
    );
    final picks = <_PhoneticPick>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final phonetic = selectPronunciation(
        parsePronunciationsJson(candidate.pronunciationsJson),
        accent,
      );
      if (phonetic == null || matchPhoneme(phonetic) == null) continue;
      if (!seen.add(phonetic.toLowerCase())) continue;
      picks.add(_PhoneticPick(candidate: candidate, phonetic: phonetic));
    }
    return picks;
  }
}
