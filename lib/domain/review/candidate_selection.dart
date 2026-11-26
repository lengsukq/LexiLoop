/// 候选抽题：把候选池变成一条有教学意图的题目序列。
///
/// 对应旧版 `modules/study/candidates.ts` 的选取部分（SQL 部分在 DAO 层）。
///
/// **为什么不用「随机打乱」**：纯随机会让一次会话里 8 道题全是新词，
/// 或者连续 5 道都是同一个错词。这里按「到期 / 错词 / 新词」三池加权抽取，
/// 并且新词占比有软上限（[dailyNewWordRatio]），使一次会话的难度曲线可控。
///
/// 随机源通过参数注入，使「给定随机序列 → 确定的题目序列」可被断言。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 可注入的随机源，返回 `[0, 1)` 区间的值。
typedef CandidateRandom = double Function();

/// 三个待抽池（会被就地消费）。
class _WorkingPools {
  new(StudyPools pools)
    : due = List<StudyCandidate>.of(pools.due),
      wrong = List<StudyCandidate>.of(pools.wrong),
      fresh = List<StudyCandidate>.of(pools.fresh);

  final List<StudyCandidate> due;
  final List<StudyCandidate> wrong;
  final List<StudyCandidate> fresh;

  /// 按下标取池。
  List<StudyCandidate> operator [](int index) => switch (index) {
    poolIndexDue => due,
    poolIndexWrong => wrong,
    _ => fresh,
  };

  /// 池内是否还有候选。
  bool get isEmpty => due.isEmpty && wrong.isEmpty && fresh.isEmpty;

  /// 仍有候选的池下标。
  List<int> get nonEmptyIndexes => <int>[
    if (due.isNotEmpty) poolIndexDue,
    if (wrong.isNotEmpty) poolIndexWrong,
    if (fresh.isNotEmpty) poolIndexFresh,
  ];

  /// 全部剩余候选数。
  int get length => due.length + wrong.length + fresh.length;
}

/// 按权重抽取一个下标。
int weightedIndex(
  int length,
  CandidateRandom random,
  double Function(int index) weightAt,
) {
  if (length <= 1) return 0;
  final weights = List<double>.generate(
    length,
    (index) => math.max(candidateWeightFloor, weightAt(index)),
  );
  final total = weights.reduce((sum, weight) => sum + weight);
  var cursor = boundedCandidateRandom(random) * total;
  for (var index = 0; index < weights.length; index += 1) {
    cursor -= weights[index];
    if (cursor < 0) return index;
  }
  return weights.length - 1;
}

/// 把随机值夹到 `[0, candidateRandomCeiling]`。
double boundedCandidateRandom(CandidateRandom random) =>
    math.min(candidateRandomCeiling, math.max(0, random()));

/// 从池中按「越靠前越可能被选中」的权重取出一项。
///
/// 只在前 [categoryLookahead] 项里抽，避免一条 SQL 的排序结果
/// 被随机性完全抹平——排序本身已编码了紧迫度。
StudyCandidate? takeWeightedCandidate(
  List<StudyCandidate> items,
  CandidateRandom random,
  StudyTaskType taskType,
) {
  if (items.isEmpty) return null;
  final lookahead = math.min(categoryLookahead, items.length);
  final index = weightedIndex(
    lookahead,
    random,
    (rank) => 1 + (lookahead - rank) / lookahead,
  );
  final candidate = items.removeAt(index);
  return candidate.withTaskType(taskType);
}

/// 单个池在当前位置的相对权重。
///
/// 新词池的权重随「已选新词数」线性衰减到 0，从而把新词占比软性限制在
/// [dailyNewWordRatio] 附近；复习池内部再按错词加成（[wrongCandidateWeightBonus]）
/// 分配，使薄弱词更早出现。
double _categoryWeight(
  int poolIndex,
  _WorkingPools pools,
  int targetFresh,
  int selectedFresh,
) {
  final remainingTotal = pools.length;
  if (remainingTotal == 0) return 0;
  final remainingFresh = math.max(0, targetFresh - selectedFresh);

  if (poolIndex == poolIndexFresh) {
    return pools.fresh.isEmpty ? 0 : remainingFresh / remainingTotal;
  }

  final remainingReviews = pools.due.length + pools.wrong.length;
  if (remainingReviews == 0) return 0;

  final reviewShare = 1 - remainingFresh / remainingTotal;
  final dueWeight = pools.due.length.toDouble();
  final wrongWeight = pools.wrong.length * wrongCandidateWeightBonus;
  final reviewWeight = dueWeight + wrongWeight;
  if (reviewWeight == 0) return 0;
  final ownWeight = poolIndex == poolIndexWrong ? wrongWeight : dueWeight;
  return reviewShare * ownWeight / reviewWeight;
}

/// 按软性新词配额与紧迫度加权，从三池混合抽取 [limit] 项。
List<StudyCandidate> selectWeightedMixed(
  StudyPools pools,
  int limit,
  CandidateRandom random,
) {
  final working = _WorkingPools(pools);
  final selected = <StudyCandidate>[];
  final targetFresh = math.min(
    working.fresh.length,
    (math.min(limit, working.length) * dailyNewWordRatio).ceil(),
  );
  var selectedFresh = 0;

  while (selected.length < limit && !working.isEmpty) {
    final available = working.nonEmptyIndexes;
    final poolIndex =
        available[weightedIndex(
          available.length,
          random,
          (position) => _categoryWeight(
            available[position],
            working,
            targetFresh,
            selectedFresh,
          ),
        )];
    final taskType = switch (poolIndex) {
      poolIndexFresh => StudyTaskType.newWord,
      poolIndexWrong => StudyTaskType.wrong,
      _ => StudyTaskType.review,
    };
    final candidate = takeWeightedCandidate(
      working[poolIndex],
      random,
      taskType,
    );
    if (candidate == null) continue;
    selected.add(candidate);
    if (poolIndex == poolIndexFresh) selectedFresh += 1;
  }
  return selected;
}

/// 按学习模式选出题目序列。
List<StudyCandidate> selectCandidates(
  StudyMode mode,
  StudyPools pools, {
  CandidateRandom? random,
}) {
  final source = random ?? _defaultRandom;
  final groups = _prioritizedGroups(pools);

  switch (mode) {
    case StudyMode.dueReview:
      return groups.due;
    case StudyMode.wrongWords:
      return groups.wrong;
    case StudyMode.newWords:
      return groups.fresh;
    case StudyMode.aiRecommended:
      return const <StudyCandidate>[];
    case StudyMode.daily:
      return selectWeightedMixed(groups, groups.length, source);
    case StudyMode.listening:
    case StudyMode.spelling:
    case StudyMode.sentenceReview:
      return _interleave(groups, _ratioFor(mode));
  }
}

/// 交错抽取的配比。
List<int> _ratioFor(StudyMode mode) => switch (mode) {
  StudyMode.listening => interleaveRatioListening,
  StudyMode.spelling => interleaveRatioSpelling,
  _ => interleaveRatioDefault,
};

/// 按各池配额裁剪并去重（同一词条只出现在一个池里）。
StudyPools _prioritizedGroups(StudyPools pools) {
  final selected = <int>{};

  List<StudyCandidate> take(List<StudyCandidate> items, int limit) {
    final result = <StudyCandidate>[];
    for (final item in items) {
      if (result.length >= limit) break;
      if (!selected.add(item.id)) continue;
      result.add(item);
    }
    return result;
  }

  return StudyPools(
    due: take(pools.due, pools.limits.due),
    wrong: take(pools.wrong, pools.limits.wrong),
    fresh: take(pools.fresh, pools.limits.fresh),
    limits: pools.limits,
  );
}

/// 按配比轮流从各池取题，并去重。
List<StudyCandidate> _interleave(StudyPools pools, List<int> ratio) {
  final groups = <List<StudyCandidate>>[pools.due, pools.wrong, pools.fresh];
  final indexes = List<int>.filled(groups.length, 0);
  final result = <StudyCandidate>[];
  final seen = <int>{};

  while (_hasRemaining(groups, indexes)) {
    for (var group = 0; group < groups.length; group += 1) {
      for (var count = 0; count < ratio[group]; count += 1) {
        if (indexes[group] >= groups[group].length) break;
        final item = groups[group][indexes[group]];
        indexes[group] += 1;
        if (seen.add(item.id)) result.add(item);
      }
    }
  }
  return result;
}

bool _hasRemaining(List<List<StudyCandidate>> groups, List<int> indexes) {
  for (var index = 0; index < groups.length; index += 1) {
    if (indexes[index] < groups[index].length) return true;
  }
  return false;
}

/// 每日软配额：用满后仍给一小段宽限（[dailyQuotaGraceRatio]）。
///
/// 硬性截断会让「今天已经学了 30 个到期词」的用户突然无题可做，
/// 即使还有大量到期卡；宽限让体验连续，同时仍能收敛。
int dailySoftLimit(int target, int used) {
  final remaining = math.max(0, target - used);
  if (used < target || target == 0) return remaining;
  final grace = math.max(1, (target * dailyQuotaGraceRatio).ceil());
  return math.max(0, target + grace - used);
}

/// 从「最久未复习」的候选里补齐不足的题量。
List<StudyCandidate> fillFromFallback(
  List<StudyCandidate> fallback,
  int needed,
  CandidateRandom random,
) {
  final selected = <StudyCandidate>[];
  while (selected.length < needed && fallback.isNotEmpty) {
    final candidate = takeWeightedCandidate(
      fallback,
      random,
      StudyTaskType.review,
    );
    if (candidate != null) selected.add(candidate);
  }
  return selected;
}

final CandidateRandom _defaultRandom = math.Random().nextDouble;
