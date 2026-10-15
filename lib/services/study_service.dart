/// 学习会话编排。
///
/// 对应旧版 `modules/study/service.ts`（`startStudySession` / `skipStudyItem`）
/// 与 `modules/study/plan.ts`（`getDailyStudyPlan`）。
///
/// 这一层只做**编排**：查候选池、选题、算题型、落库、读回视图。
/// 具体 SQL 在 `StudyDao`，选题与题型规则在 `domain/review/`。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/candidate_selection.dart';
import 'package:lexiloop/domain/review/question_type.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 跳过的默认原因。
const String defaultSkipReason = 'LATER';

/// 学习会话编排入口。
class StudyService {
  /// 以数据库与设置服务构造。
  new(AppDatabase database, this._settings) : _study = StudyDao(database);

  final SettingsService _settings;
  final StudyDao _study;

  /// 开始（或恢复）一次学习会话。
  ///
  /// [resume] 为真时优先恢复未完成的同类会话——用户中途退出应用是常态，
  /// 每次重新抽题会让「今天学了什么」变得不可预期。
  ///
  /// [continuous] 只在每日模式下生效：队列抽空后继续补题。
  Future<StudySessionView> startSession({
    required StudyMode mode,
    required int now,
    bool resume = true,
    bool continuous = false,
  }) async {
    await _study.expireStaleSessions(now);

    if (resume) {
      final resumableId = await _study.findResumableSession(mode, now);
      if (resumableId != null) {
        return await _study.loadSession(resumableId, resumed: true);
      }
    }

    final scope = _scopeFor(mode);
    final pools = await _study.loadPools(
      now: now,
      scope: scope,
      applyDailySoftQuota: mode == StudyMode.daily,
    );
    final recommended = mode == StudyMode.aiRecommended
        ? await _study.aiRecommendedCandidates(now)
        : null;
    if (mode == StudyMode.aiRecommended && (recommended?.isEmpty ?? true)) {
      throw const ConflictError(AppErrorCode.aiRecommendedAllDone);
    }

    var selected =
        recommended ?? selectCandidates(mode, pools, random: _random);
    if (mode == StudyMode.daily && continuous && selected.isEmpty) {
      selected = await _continuousCandidates(
        limit: continuousBatchSize,
        now: now,
        scope: CandidateScope.lexical,
      );
    }

    final drafts = await _buildDrafts(
      mode: mode,
      selected: selected,
      pools: pools,
      now: now,
    );
    final sessionId = await _study.createSession(
      mode: _persistedMode(mode),
      sourceType: _sourceType(mode),
      items: drafts,
      now: now,
    );
    return await _study.loadSession(sessionId);
  }

  /// 跳过一道题。
  Future<StudySessionView> skipItem({
    required int sessionId,
    required int itemId,
    required int now,
    String reason = defaultSkipReason,
  }) => _study.skipItem(
    sessionId: sessionId,
    itemId: itemId,
    reason: reason,
    now: now,
  );

  /// 组装今日学习计划。
  Future<DailyStudyPlan> dailyPlan({required int now}) async {
    final active = await _study.activePendingPlan(now);
    final lexical = await _study.loadPools(
      now: now,
      scope: CandidateScope.lexical,
      applyDailySoftQuota: true,
    );
    final sentence = await _study.loadPools(
      now: now,
      scope: CandidateScope.sentence,
    );
    final selected = selectCandidates(
      StudyMode.daily,
      lexical,
      random: _random,
    );
    final selectedSentences = selectCandidates(
      StudyMode.sentenceReview,
      sentence,
      random: _random,
    );

    final dueIds = lexical.due.map((item) => item.id).toSet();
    final wrongIds = lexical.wrong.map((item) => item.id).toSet();
    final planned = _plannedCounts(active, selected, dueIds, wrongIds);

    final available = await _study.countAvailable(
      now: now,
      scope: CandidateScope.lexical,
    );
    final sentenceAvailable = await _study.countAvailable(
      now: now,
      scope: CandidateScope.sentence,
    );
    final activeSentences = await _study.activePendingSentenceCount(now);
    final activeTotal = active.due + active.wrong + active.fresh;
    final plannedTotal = activeTotal + selected.length;

    return DailyStudyPlan(
      dueReviewCount: available.due + active.due,
      plannedDueReviewCount: planned.due,
      wrongWordCount: available.wrong + active.wrong,
      plannedWrongWordCount: planned.wrong,
      newWordCount: available.fresh + active.fresh,
      plannedNewWordCount: planned.fresh,
      sentenceReviewCount:
          sentenceAvailable.due +
          sentenceAvailable.wrong +
          sentenceAvailable.fresh +
          activeSentences,
      plannedSentenceReviewCount: selectedSentences.length + activeSentences,
      plannedTotal: plannedTotal,
      activeSessionTasks: activeTotal,
      estimatedMinutes: _estimateMinutes(planned),
    );
  }

  /// 按模式决定候选池范围。
  CandidateScope _scopeFor(StudyMode mode) => switch (mode) {
    StudyMode.sentenceReview => CandidateScope.sentence,
    StudyMode.aiRecommended => CandidateScope.all,
    _ => CandidateScope.lexical,
  };

  /// 落库的会话类型。
  ///
  /// AI 推荐与句子复习借用了其他模式的题目构成，因此 `session_type` 记成
  /// 它们实际使用的模式，真正的来源放在 `source_type` 里。
  StudyMode _persistedMode(StudyMode mode) => switch (mode) {
    StudyMode.aiRecommended => StudyMode.wrongWords,
    StudyMode.sentenceReview => StudyMode.dueReview,
    _ => mode,
  };

  String? _sourceType(StudyMode mode) =>
      mode == StudyMode.aiRecommended || mode == StudyMode.sentenceReview
      ? mode.wire
      : null;

  /// 为每个候选算出任务类型与题型。
  Future<List<StudySessionItemDraft>> _buildDrafts({
    required StudyMode mode,
    required List<StudyCandidate> selected,
    required StudyPools pools,
    required int now,
  }) async {
    if (selected.isEmpty) return const <StudySessionItemDraft>[];

    final settings = await _settings.load();
    final config = settings.questionTypeConfig;
    final examples = await _study.hasExampleMap(
      selected.map((item) => item.id).toList(growable: false),
    );
    final dueIds = pools.due.map((item) => item.id).toSet();
    final wrongIds = pools.wrong.map((item) => item.id).toSet();
    final questionMode = mode == StudyMode.aiRecommended
        ? StudyMode.daily
        : mode;

    final drafts = <StudySessionItemDraft>[];
    for (var index = 0; index < selected.length; index += 1) {
      final candidate = selected[index];
      final taskType = taskFor(
        mode: questionMode,
        candidate: candidate,
        dueIds: dueIds,
        wrongIds: wrongIds,
      );
      final context = QuestionTypeContext(
        term: candidate.term,
        hasExample: examples[candidate.id] ?? false,
      );
      drafts.add(
        StudySessionItemDraft(
          wordId: candidate.id,
          taskType: taskType,
          questionType: _questionTypeFor(
            candidate: candidate,
            taskType: taskType,
            questionMode: questionMode,
            context: context,
            config: config,
            index: index,
          ),
        ),
      );
    }
    return drafts;
  }

  QuestionType _questionTypeFor({
    required StudyCandidate candidate,
    required StudyTaskType taskType,
    required StudyMode questionMode,
    required QuestionTypeContext context,
    required QuestionTypeConfig config,
    required int index,
  }) {
    final recommended = candidate.recommendedQuestionType;
    if (recommended != null) {
      return resolveQuestionType(
        preferred: recommended,
        mode: questionMode,
        taskType: taskType,
        context: context,
        config: config,
        random: _random,
      );
    }
    return questionFor(
      mode: questionMode,
      taskType: taskType,
      context: context,
      config: config,
      position: index,
      masteryScore: candidate.masteryScore,
      random: _random,
    );
  }

  /// 每日队列抽空后的补齐批次。
  Future<List<StudyCandidate>> _continuousCandidates({
    required int limit,
    required int now,
    required CandidateScope scope,
  }) async {
    final due = await _study.dueCandidates(
      limit: limit,
      now: now,
      scope: scope,
    );
    final dueIds = due.map((item) => item.id).toSet();
    final wrong = (await _study.wrongCandidates(
      limit: limit,
      now: now,
      scope: scope,
    )).where((item) => !dueIds.contains(item.id)).toList(growable: false);
    final reviewIds = <int>{...dueIds, ...wrong.map((item) => item.id)};
    final fresh = (await _study.newCandidates(
      limit: limit,
      now: now,
      scope: scope,
    )).where((item) => !reviewIds.contains(item.id)).toList(growable: false);

    final pools = StudyPools(
      due: due,
      wrong: wrong,
      fresh: fresh,
      limits: PoolLimits(due: limit, wrong: limit, fresh: limit),
    );
    final selected = selectWeightedMixed(pools, limit, _random);
    final remaining = limit - selected.length;
    if (remaining <= 0) return selected;

    final fallback = await _study.leastRecentlyReviewedCandidates(
      limit: remaining,
      now: now,
      scope: scope,
      excludedIds: selected.map((item) => item.id).toSet(),
    );
    return <StudyCandidate>[
      ...selected,
      ...fillFromFallback(fallback, remaining, _random),
    ];
  }

  /// 把「活跃会话里未答的题」与「本次新选的题」合并成计划数。
  PoolLimits _plannedCounts(
    PoolLimits active,
    List<StudyCandidate> selected,
    Set<int> dueIds,
    Set<int> wrongIds,
  ) {
    var due = active.due;
    var wrong = active.wrong;
    var fresh = active.fresh;
    for (final candidate in selected) {
      if (dueIds.contains(candidate.id)) {
        due += 1;
      } else if (wrongIds.contains(candidate.id)) {
        wrong += 1;
      } else {
        fresh += 1;
      }
    }
    return PoolLimits(due: due, wrong: wrong, fresh: fresh);
  }

  /// 预估耗时：三类题的单题耗时不同，新词最慢。
  int _estimateMinutes(PoolLimits planned) {
    final total = planned.due + planned.wrong + planned.fresh;
    if (total == 0) return 0;
    final seconds =
        planned.due * estimatedSecondsPerReview +
        planned.wrong * estimatedSecondsPerWrong +
        planned.fresh * estimatedSecondsPerNew;
    final minutes = (seconds / (minuteMs ~/ secondMs)).ceil();
    return math.max(1, minutes);
  }
}

final CandidateRandom _random = math.Random().nextDouble;
