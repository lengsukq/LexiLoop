/// 作答处理流水线。
///
/// 对应旧版 `modules/reviews/service.ts` 的 `processReviewAnswer`。
///
/// **原子性**：整条流水线跑在一个事务里——认领题目、推进 FSRS、写日志、
/// 重算统计、更新错词状态、更新熟练度、插入追问题、收尾会话。任何一步失败
/// 都必须整体回滚，否则会出现「卡片推进了但没有日志」这类无法对账的状态。
///
/// **幂等**：入口先按 `client_answer_id` 查日志。命中时校验上下文一致后
/// 直接回显既有结果，不重复推进 FSRS。无服务端之后这条约束比旧版更重要：
/// 界面重放、误触连点都会走同一条路径。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/domain/review/mastery.dart';
import 'package:lexiloop/domain/review/question_type.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 配对游戏的会话来源标识。
const String matchGameSourceType = 'MATCH_GAME';

/// 小游戏会话来源标识的前缀。
const String gameSourcePrefix = 'GAME_';

/// 作答处理入口。
class ReviewService {
  /// 以数据库与设置服务构造。
  ///
  /// 用位置参数而不是具名参数：字段是私有的，而 Dart 禁止下划线开头的
  /// 具名参数，因此无法写成 `this._database`；手工赋值又会触发
  /// `prefer_initializing_formals`。
  new(this._database, this._settings)
    : _review = ReviewDao(_database),
      _study = StudyDao(_database);

  final AppDatabase _database;
  final SettingsService _settings;
  final ReviewDao _review;
  final StudyDao _study;

  /// 按目标保持率缓存的调度器。
  ///
  /// `package:fsrs` 的调度器把保持率固化在内部，而保持率来自设置。
  /// 旧版为此维护了一个无上限的全局 Map（见 `docs/CLEAN_CODE_BASELINE.md`）；
  /// 这里只缓存最近用到的**一个**——设置页改动会立刻让旧实例失去意义。
  double? _cachedRetention;
  FsrsScheduler? _cachedScheduler;

  /// 处理一次作答。
  ///
  /// [now] 由调用方注入，便于测试构造确定的时间线。
  Future<ReviewOutcome> processAnswer(
    AnswerInput input, {
    required int now,
  }) async {
    final settings = await _settings.load();
    return await _database.transaction(() => _process(input, settings, now));
  }

  /// 处理一批作答（练习与小游戏结算走这里）。
  ///
  /// 整批共用一个事务：小游戏结算要么全部计入，要么全部不计入，
  /// 否则中途失败会留下「玩了一半的分数」。
  Future<List<ReviewOutcome>> processAnswers(
    List<AnswerInput> inputs, {
    required int now,
  }) async {
    final settings = await _settings.load();
    return await _database.transaction(() async {
      final outcomes = <ReviewOutcome>[];
      for (final input in inputs) {
        outcomes.add(await _process(input, settings, now));
      }
      return outcomes;
    });
  }

  /// 预览某词条四个评级各自的排期。
  Future<List<FsrsIntervalPreview>> previewIntervals(
    int wordId, {
    required int now,
  }) async {
    final settings = await _settings.load();
    final scheduler = _schedulerFor(settings.studyPlan.targetRetentionRate);
    final card = await _review.findCard(wordId);
    return scheduler.preview(
      card: card ?? scheduler.emptyCard(now),
      nowMs: now,
    );
  }

  Future<ReviewOutcome> _process(
    AnswerInput input,
    AppSettings settings,
    int now,
  ) async {
    final existing = await _review.findExistingLog(input.clientAnswerId);
    if (existing != null) {
      _assertSameContext(existing, input);
      return await _idempotentOutcome(existing);
    }

    if (input.hasSessionContext) {
      await _review.claimStudyItem(
        sessionId: input.studySessionId!,
        itemId: input.studySessionItemId!,
        wordId: input.wordId,
        questionType: input.questionType,
        now: now,
      );
    }

    // 词条、卡片、错词状态一次查回，避免同一份上下文被查三遍。
    final context = await _review.findContext(input.wordId);
    final word = _assertReviewable(context.word);
    final evaluation = evaluateAnswer(input, word);
    final scheduler = _schedulerFor(settings.studyPlan.targetRetentionRate);
    final before = context.card ?? scheduler.emptyCard(now);
    final after = scheduler.schedule(
      card: before,
      nowMs: now,
      rating: evaluation.effectiveRating,
    );

    final reviewLogId = await _review.insertCardAndLog(
      answer: input,
      reviewedAt: now,
      rating: evaluation.effectiveRating,
      presentedPrompt: evaluation.presentedPrompt,
      expectedAnswer: evaluation.expectedAnswer,
      isCorrect: evaluation.isCorrect,
      before: before,
      after: after,
      now: now,
    );

    final statistics = await _review.upsertWordReviewStats(
      wordId: word.id,
      reviewedAt: now,
      isCorrect: evaluation.isCorrect,
      durationMs: input.durationMs,
    );

    final transition = transitionWrongState(
      current: context.wrongState,
      rating: evaluation.effectiveRating,
      isCorrect: evaluation.isCorrect,
      now: now,
    );
    if (transition != null) {
      await _review.saveWrongState(word.id, transition, now);
    }
    final wrongState = wrongStateResultOf(transition);

    final masteryInput = MasteryInput(
      stability: after.stability,
      scheduledDays: after.scheduledDays,
      reps: after.reps,
      lapses: after.lapses,
      accuracy: statistics.accuracy,
      consecutiveCorrect: wrongState.consecutiveCorrect,
      activeWrongWord: wrongState.active,
      recentAgain: statistics.recentAgain,
      averageDurationMs: statistics.averageDurationMs,
    );
    final masteryScore = calculateMasteryScore(masteryInput);
    final masteryLevel = determineMasteryLevel(masteryInput, masteryScore);
    await _review.updateMastery(word.id, masteryScore, masteryLevel, now);

    // 追问题必须在收尾会话之前插入：收尾会在没有 PENDING 题目时盖上
    // completed_at，而已完成会话不再接受插题。顺序颠倒会导致
    // 「最后一道题答错时拿不到追问题」。
    final followUp = input.hasSessionContext
        ? await _scheduleFollowUp(input, word, evaluation, now)
        : null;

    if (input.hasSessionContext) {
      await _review.finalizeSession(
        sessionId: input.studySessionId!,
        isCorrect: evaluation.isCorrect,
        now: now,
      );
    }

    return ReviewOutcome(
      reviewLogId: reviewLogId,
      isCorrect: evaluation.isCorrect,
      rating: evaluation.effectiveRating,
      expectedAnswer: evaluation.expectedAnswer,
      nextDueAt: after.dueAt,
      scheduledDays: after.scheduledDays,
      masteryScore: masteryScore,
      masteryLevel: masteryLevel,
      wrongWordActive: wrongState.active,
      idempotent: false,
      adaptiveFollowUp: followUp,
    );
  }

  /// 幂等命中时回显既有结果。
  Future<ReviewOutcome> _idempotentOutcome(ExistingReviewLog existing) async {
    final card = await _review.findCard(existing.wordId);
    final mastery = await _review.findMastery(existing.wordId);
    final context = await _review.findContext(existing.wordId);
    return ReviewOutcome(
      reviewLogId: existing.id,
      isCorrect: existing.isCorrect,
      rating: existing.rating,
      expectedAnswer: existing.expectedAnswer ?? '',
      nextDueAt: card?.dueAt,
      scheduledDays: card?.scheduledDays ?? 0,
      masteryScore: mastery?.score ?? 0,
      masteryLevel: mastery?.level ?? MasteryLevel.newWord,
      wrongWordActive: context.wrongState?.active ?? false,
      idempotent: true,
    );
  }

  /// 同一幂等键只能对应同一个上下文。
  ///
  /// 键相同但词条或会话题目不同，说明客户端复用了键——这是 bug，
  /// 静默接受会让两次作答互相覆盖。
  void _assertSameContext(ExistingReviewLog existing, AnswerInput input) {
    final sameContext =
        existing.wordId == input.wordId &&
        existing.studySessionId == input.studySessionId &&
        existing.studySessionItemId == input.studySessionItemId;
    if (!sameContext) {
      throw const ConflictError(AppErrorCode.idempotencyKeyConflict);
    }
  }

  ReviewWord _assertReviewable(ReviewWord? word) {
    if (word == null) throw const NotFoundError(AppErrorCode.wordNotFound);
    if (word.isSuspended) throw const ConflictError(AppErrorCode.wordSuspended);
    if (!word.isReviewable) {
      throw const ConflictError(AppErrorCode.wordNotReady);
    }
    return word;
  }

  /// 会话内插题。
  ///
  /// **与旧版的差异（修正了一处缺陷）**：旧版用「本词在会话内已 ANSWERED
  /// 的题目数」判断这是第几次错，但认领当前题目时它已经被置为 ANSWERED，
  /// 因此计数永远 ≥1——结果是「首次错隔 5 题复现」成了死代码，每个词在一次
  /// 会话内最多只插一道题。这里改为统计**本次之前**的作答次数，使
  /// 「首次错隔 5 题、二次错隔 10 题、最多 2 次」按设计生效。
  Future<AdaptiveFollowUp?> _scheduleFollowUp(
    AnswerInput input,
    ReviewWord word,
    AnswerEvaluation evaluation,
    int now,
  ) async {
    // 只有「完全遗忘」才在当前会话内复现。「模糊」已进错词本，
    // 留给后续会话处理，否则会打断当前节奏。
    final forgotten =
        !evaluation.isCorrect &&
        evaluation.effectiveRating != ReviewRating.hard;
    if (!forgotten) return null;

    final sessionId = input.studySessionId!;
    final head = await _study.findSessionHead(sessionId);
    if (head == null || head.completedAt != null) return null;
    if (_isExcludedSource(head.sourceType)) return null;

    final answered = await _study.answeredCountInSession(
      sessionId: sessionId,
      wordId: word.id,
    );
    final answeredBefore = answered > 0 ? answered - 1 : 0;
    if (answeredBefore >= maxFollowUpsPerWord) return null;

    // 已有一道未作答的追问题时不叠加，避免同一词连续出现。
    final pending = await _study.pendingCountInSession(
      sessionId: sessionId,
      wordId: word.id,
    );
    if (pending > 0) return null;

    final currentPosition = await _study.findItemPosition(
      sessionId: sessionId,
      itemId: input.studySessionItemId!,
    );
    if (currentPosition == null) return null;

    final delay = answeredBefore == 0
        ? firstFollowUpDelay
        : secondFollowUpDelay;
    final position = await _resolveFollowUpPosition(
      sessionId: sessionId,
      currentPosition: currentPosition,
      delay: delay,
    );
    final questionType = await _resolveFollowUpQuestionType(
      current: input.questionType,
      word: word,
    );

    await _study.insertFollowUpItem(
      sessionId: sessionId,
      wordId: word.id,
      questionType: questionType,
      position: position,
      now: now,
    );
    return AdaptiveFollowUp(
      questionType: questionType,
      position: position,
      repetition: answeredBefore,
    );
  }

  /// 算出追问的插入位置：落在「当前题之后第 delay 题」与其前一项之间。
  ///
  /// 位置是浮点且带 `(study_session_id, position)` 唯一索引。反复在同一
  /// 间隙取中点会逼近浮点精度极限，因此插值结果必须严格落在两端点之间；
  /// 一旦退化（或剩余题数不足 delay），就追加到队尾。
  Future<double> _resolveFollowUpPosition({
    required int sessionId,
    required double currentPosition,
    required int delay,
  }) async {
    final target = await _study.positionAtOffset(
      sessionId: sessionId,
      afterPosition: currentPosition,
      offset: delay - 1,
    );
    if (target == null) {
      return await _appendPosition(sessionId, currentPosition);
    }

    final previous = await _study.previousPositionBefore(
      sessionId: sessionId,
      position: target,
    );
    if (previous == null) return await _appendPosition(sessionId, target);

    final interpolated =
        previous + (target - previous) * sessionItemPositionStep;
    if (interpolated <= previous || interpolated >= target) {
      return await _appendPosition(sessionId, target);
    }
    return interpolated;
  }

  Future<double> _appendPosition(int sessionId, double fallback) async {
    final last = await _study.lastItemPosition(sessionId);
    return (last ?? fallback) + sessionItemAppendStep;
  }

  Future<QuestionType> _resolveFollowUpQuestionType({
    required QuestionType current,
    required ReviewWord word,
  }) async {
    final settings = await _settings.load();
    final examples = await _study.hasExampleMap(<int>[word.id]);
    return resolveAdaptiveQuestionType(
      preferred: nextAdaptiveQuestionType(current, word.contentType),
      context: QuestionTypeContext(
        term: word.term,
        hasExample: examples[word.id] ?? false,
      ),
      config: settings.questionTypeConfig,
    );
  }

  /// 小游戏与配对会话不参与自适应插题——它们有自己的结算与重播规则。
  bool _isExcludedSource(String? sourceType) {
    if (sourceType == null) return false;
    return sourceType == matchGameSourceType ||
        sourceType.startsWith(gameSourcePrefix);
  }

  FsrsScheduler _schedulerFor(double retention) {
    final cached = _cachedScheduler;
    if (cached != null && _cachedRetention == retention) return cached;
    final scheduler = FsrsScheduler(requestRetention: retention);
    _cachedRetention = retention;
    _cachedScheduler = scheduler;
    return scheduler;
  }
}
