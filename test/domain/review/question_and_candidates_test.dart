/// 题型选择与候选抽题的单元测试。
///
/// 这两个模块都带随机性，因此全部通过注入随机源来获得确定性结果；
/// 否则只能断言「返回了某个合法值」，等于没测。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/candidate_selection.dart';
import 'package:lexiloop/domain/review/question_type.dart';

/// 始终返回同一个值的随机源。
double Function() _fixed(double value) =>
    () => value;

/// 按顺序循环返回预设值的随机源。
double Function() _sequence(List<double> values) {
  var index = 0;
  return () {
    final value = values[index % values.length];
    index += 1;
    return value;
  };
}

/// 构造题型配置：只启用给定题型。
QuestionTypeConfig _onlyTypes(Set<QuestionType> enabled) =>
    QuestionTypeConfig(<QuestionType, QuestionTypeSetting>{
      for (final type in QuestionType.values)
        type: QuestionTypeSetting(
          enabled: enabled.contains(type),
          weight: defaultQuestionTypeWeight,
        ),
    });

StudyCandidate _candidate(int id, {StudyTaskType? taskType}) => StudyCandidate(
  id: id,
  term: 'term$id',
  normalizedTerm: 'term$id',
  sourceLanguage: 'en',
  targetLanguage: 'zh',
  contentType: LexicalContentType.word,
  continuousTaskType: taskType,
);

StudyPools _pools({
  int due = 0,
  int wrong = 0,
  int fresh = 0,
  int dueLimit = 100,
  int wrongLimit = 100,
  int freshLimit = 100,
}) => StudyPools(
  due: <StudyCandidate>[for (var i = 0; i < due; i += 1) _candidate(i)],
  wrong: <StudyCandidate>[
    for (var i = 0; i < wrong; i += 1) _candidate(1000 + i),
  ],
  fresh: <StudyCandidate>[
    for (var i = 0; i < fresh; i += 1) _candidate(2000 + i),
  ],
  limits: PoolLimits(due: dueLimit, wrong: wrongLimit, fresh: freshLimit),
);

void main() {
  group('isQuestionTypeEligible', () {
    test('没有例句时不能出填空题', () {
      expect(
        isQuestionTypeEligible(
          QuestionType.clozeSentence,
          const QuestionTypeContext(),
        ),
        isFalse,
      );
      expect(
        isQuestionTypeEligible(
          QuestionType.clozeSentence,
          const QuestionTypeContext(hasExample: true),
        ),
        isTrue,
      );
    });

    test('字母拼图只适用于 3–14 个纯字母', () {
      for (final term in <String>['abc', 'hello', 'abcdefghijklmn']) {
        expect(
          isQuestionTypeEligible(
            QuestionType.letterBank,
            QuestionTypeContext(term: term),
          ),
          isTrue,
          reason: term,
        );
      }
      for (final term in <String>['ab', 'a', '', 'hello world', 'a-b', '词条']) {
        expect(
          isQuestionTypeEligible(
            QuestionType.letterBank,
            QuestionTypeContext(term: term),
          ),
          isFalse,
          reason: term,
        );
      }
    });

    test('其他题型总是可用', () {
      expect(
        isQuestionTypeEligible(
          QuestionType.zhToEnSpelling,
          const QuestionTypeContext(),
        ),
        isTrue,
      );
    });
  });

  group('resolveQuestionType', () {
    test('首选可用时直接用首选', () {
      final result = resolveQuestionType(
        preferred: QuestionType.zhToEnSpelling,
        mode: StudyMode.daily,
        taskType: StudyTaskType.review,
        context: const QuestionTypeContext(term: 'apple'),
        config: QuestionTypeConfig.defaults,
        random: _fixed(0.5),
      );
      expect(result, QuestionType.zhToEnSpelling);
    });

    test('首选被禁用时回退到模式池', () {
      final result = resolveQuestionType(
        preferred: QuestionType.zhToEnSpelling,
        mode: StudyMode.listening,
        taskType: StudyTaskType.listening,
        context: const QuestionTypeContext(term: 'apple'),
        config: _onlyTypes(<QuestionType>{QuestionType.listeningChoice}),
        random: _fixed(0.5),
      );
      expect(result, QuestionType.listeningChoice);
    });

    test('首选不可用（缺例句）时回退', () {
      final result = resolveQuestionType(
        preferred: QuestionType.clozeSentence,
        mode: StudyMode.daily,
        taskType: StudyTaskType.review,
        context: const QuestionTypeContext(term: 'apple'),
        config: _onlyTypes(<QuestionType>{QuestionType.enToZhChoice}),
        random: _fixed(0.5),
      );
      expect(result, QuestionType.enToZhChoice);
    });

    test('模式池也全不可用时走全局兜底', () {
      final result = resolveQuestionType(
        preferred: QuestionType.clozeSentence,
        mode: StudyMode.listening,
        taskType: StudyTaskType.listening,
        context: const QuestionTypeContext(),
        config: _onlyTypes(<QuestionType>{QuestionType.enToZh}),
        random: _fixed(0.5),
      );
      expect(result, QuestionType.enToZh);
    });

    test('一个题型都没启用时收敛为默认配置，不会抛异常', () {
      final config = _onlyTypes(const <QuestionType>{}).normalized;
      expect(config.hasEnabledType, isTrue);
      expect(
        resolveQuestionType(
          preferred: QuestionType.zhToEnSpelling,
          mode: StudyMode.daily,
          taskType: StudyTaskType.review,
          context: const QuestionTypeContext(term: 'apple'),
          config: config,
          random: _fixed(0.5),
        ),
        QuestionType.zhToEnSpelling,
      );
    });

    test('权重影响抽中概率', () {
      // 两个候选题型，第一个权重极低、第二个极高，随机值偏大时应选后者。
      final config = QuestionTypeConfig(<QuestionType, QuestionTypeSetting>{
        for (final type in QuestionType.values)
          type: QuestionTypeSetting(
            enabled:
                type == QuestionType.enToZhChoice ||
                type == QuestionType.zhToEnChoice,
            weight: type == QuestionType.zhToEnChoice
                ? maxQuestionTypeWeight
                : minQuestionTypeWeight,
          ),
      });
      final result = resolveQuestionType(
        preferred: QuestionType.enToZh,
        mode: StudyMode.daily,
        taskType: StudyTaskType.review,
        context: const QuestionTypeContext(term: 'apple'),
        config: config,
        random: _fixed(0.9),
      );
      expect(result, QuestionType.zhToEnChoice);
    });
  });

  group('resolveAdaptiveQuestionType', () {
    test('首选可用时保持首选', () {
      expect(
        resolveAdaptiveQuestionType(
          preferred: QuestionType.zhToEnSpelling,
          context: const QuestionTypeContext(term: 'apple'),
          config: QuestionTypeConfig.defaults,
          random: _fixed(0.5),
        ),
        QuestionType.zhToEnSpelling,
      );
    });

    test('首选不可用时只从听力池里挑', () {
      final result = resolveAdaptiveQuestionType(
        preferred: QuestionType.listeningSpelling,
        context: const QuestionTypeContext(),
        config: _onlyTypes(<QuestionType>{QuestionType.listeningChoice}),
        random: _fixed(0.5),
      );
      expect(result, QuestionType.listeningChoice);
    });

    test('听力池全不可用时退回拼写类', () {
      final result = resolveAdaptiveQuestionType(
        preferred: QuestionType.listeningSpelling,
        context: const QuestionTypeContext(term: 'apple'),
        config: _onlyTypes(<QuestionType>{QuestionType.zhToEnSpelling}),
        random: _fixed(0.5),
      );
      expect(result, QuestionType.zhToEnSpelling);
    });
  });

  group('questionFor', () {
    QuestionType ask(
      StudyMode mode,
      StudyTaskType taskType, {
      int position = 0,
      int? masteryScore,
      String term = 'apple',
      bool hasExample = false,
      QuestionTypeConfig? config,
    }) => questionFor(
      mode: mode,
      taskType: taskType,
      context: QuestionTypeContext(term: term, hasExample: hasExample),
      config: config ?? QuestionTypeConfig.defaults,
      position: position,
      masteryScore: masteryScore,
      random: _fixed(0),
    );

    test('句子复习：新句用看英选中，复习用拼写', () {
      expect(
        ask(StudyMode.sentenceReview, StudyTaskType.newWord),
        QuestionType.enToZh,
      );
      expect(
        ask(StudyMode.sentenceReview, StudyTaskType.review),
        QuestionType.zhToEnSpelling,
      );
    });

    test('听力：奇数位置出选择题，偶数位置出拼写题', () {
      expect(
        ask(StudyMode.listening, StudyTaskType.listening),
        QuestionType.listeningSpelling,
      );
      expect(
        ask(StudyMode.listening, StudyTaskType.listening, position: 1),
        QuestionType.listeningChoice,
      );
      expect(
        ask(StudyMode.listening, StudyTaskType.listening, position: 2),
        QuestionType.listeningSpelling,
      );
    });

    test('听力：弱项（熟练分低于阈值）在特定位置降级为选择题', () {
      expect(
        ask(
          StudyMode.listening,
          StudyTaskType.listening,
          position: listeningWeakMasteryOffset,
          masteryScore: listeningWeakMasteryScore - 1,
        ),
        QuestionType.listeningChoice,
      );
    });

    test('拼写：位置是字母拼图周期的整数倍时出字母拼图', () {
      expect(
        ask(StudyMode.spelling, StudyTaskType.spelling),
        QuestionType.letterBank,
      );
      expect(
        ask(StudyMode.spelling, StudyTaskType.spelling, position: 1),
        QuestionType.zhToEnSpelling,
      );
    });

    test('拼写：词条不适合字母拼图时退回拼写题', () {
      expect(
        ask(StudyMode.spelling, StudyTaskType.spelling, term: 'hello world'),
        QuestionType.zhToEnSpelling,
      );
    });

    test('错词任务优先于每日模式，按拼写规则出题', () {
      expect(
        ask(StudyMode.daily, StudyTaskType.wrong),
        QuestionType.letterBank,
      );
      expect(
        ask(StudyMode.daily, StudyTaskType.wrong, position: 1),
        QuestionType.zhToEnSpelling,
      );
    });

    test('听力模式里的错词仍按听力规则出题', () {
      expect(
        ask(StudyMode.listening, StudyTaskType.wrong),
        QuestionType.listeningSpelling,
      );
      expect(
        ask(StudyMode.listening, StudyTaskType.wrong, position: 1),
        QuestionType.listeningChoice,
      );
    });

    test('每日：新词用看英选中', () {
      expect(ask(StudyMode.daily, StudyTaskType.newWord), QuestionType.enToZh);
    });

    test('每日：熟练分分层决定题型', () {
      expect(
        ask(
          StudyMode.daily,
          StudyTaskType.review,
          masteryScore: dailyLowMasteryScore - 1,
        ),
        QuestionType.enToZhChoice,
      );
      expect(
        ask(
          StudyMode.daily,
          StudyTaskType.review,
          masteryScore: dailyLowMasteryScore,
          hasExample: true,
        ),
        QuestionType.clozeSentence,
      );
      expect(
        ask(
          StudyMode.daily,
          StudyTaskType.review,
          masteryScore: dailyMediumMasteryScore,
        ),
        QuestionType.zhToEnChoice,
      );
      expect(
        ask(
          StudyMode.daily,
          StudyTaskType.review,
          masteryScore: dailyHighMasteryScore,
          position: 1,
        ),
        QuestionType.zhToEnSpelling,
      );
    });

    test('每日：没有熟练分时按位置交替选择题', () {
      expect(
        ask(StudyMode.daily, StudyTaskType.review),
        QuestionType.enToZhChoice,
      );
      expect(
        ask(StudyMode.daily, StudyTaskType.review, position: 1),
        QuestionType.zhToEnChoice,
      );
    });

    test('每日：无熟练分时填空题只在有例句的位置出现', () {
      expect(
        ask(
          StudyMode.daily,
          StudyTaskType.review,
          position: dailyClozeOffset,
          hasExample: true,
        ),
        QuestionType.clozeSentence,
      );
      expect(
        ask(StudyMode.daily, StudyTaskType.review, position: dailyClozeOffset),
        QuestionType.zhToEnChoice,
      );
    });

    test('到期复习与新词学习默认出看英选中', () {
      for (final mode in <StudyMode>[StudyMode.dueReview, StudyMode.newWords]) {
        expect(
          ask(mode, StudyTaskType.review),
          QuestionType.enToZhChoice,
          reason: mode.wire,
        );
      }
    });
  });

  group('taskFor', () {
    late StudyCandidate candidate;

    setUp(() => candidate = _candidate(1));

    test('模式直接决定任务类型', () {
      expect(
        taskFor(
          mode: StudyMode.listening,
          candidate: candidate,
          dueIds: <int>{1},
          wrongIds: <int>{1},
        ),
        StudyTaskType.listening,
      );
      expect(
        taskFor(
          mode: StudyMode.spelling,
          candidate: candidate,
          dueIds: <int>{1},
          wrongIds: <int>{1},
        ),
        StudyTaskType.spelling,
      );
      expect(
        taskFor(
          mode: StudyMode.dueReview,
          candidate: candidate,
          dueIds: <int>{},
          wrongIds: <int>{},
        ),
        StudyTaskType.review,
      );
      expect(
        taskFor(
          mode: StudyMode.newWords,
          candidate: candidate,
          dueIds: <int>{1},
          wrongIds: <int>{},
        ),
        StudyTaskType.newWord,
      );
    });

    test('连续学习预设的任务类型优先于集合推断', () {
      expect(
        taskFor(
          mode: StudyMode.daily,
          candidate: _candidate(1, taskType: StudyTaskType.newWord),
          dueIds: <int>{1},
          wrongIds: <int>{},
        ),
        StudyTaskType.newWord,
      );
    });

    test('集合推断：到期优先于错词', () {
      expect(
        taskFor(
          mode: StudyMode.daily,
          candidate: candidate,
          dueIds: <int>{1},
          wrongIds: <int>{1},
        ),
        StudyTaskType.review,
      );
      expect(
        taskFor(
          mode: StudyMode.daily,
          candidate: candidate,
          dueIds: <int>{},
          wrongIds: <int>{1},
        ),
        StudyTaskType.wrong,
      );
      expect(
        taskFor(
          mode: StudyMode.daily,
          candidate: candidate,
          dueIds: <int>{},
          wrongIds: <int>{},
        ),
        StudyTaskType.newWord,
      );
    });
  });

  group('dailySoftLimit', () {
    test('未用满时返回剩余额度', () {
      expect(dailySoftLimit(30, 0), 30);
      expect(dailySoftLimit(30, 10), 20);
    });

    test('刚好用满时给出一段宽限', () {
      final grace = (30 * dailyQuotaGraceRatio).ceil();
      expect(dailySoftLimit(30, 30), grace);
    });

    test('超出宽限后归零，不再为负', () {
      expect(dailySoftLimit(30, 1000), 0);
    });

    test('额度为 0 时始终为 0', () {
      expect(dailySoftLimit(0, 0), 0);
      expect(dailySoftLimit(0, 5), 0);
    });
  });

  group('selectCandidates', () {
    test('到期复习模式只取 due 池并受配额限制', () {
      final selected = selectCandidates(
        StudyMode.dueReview,
        _pools(due: 10, wrong: 10, fresh: 10, dueLimit: 3),
        random: _fixed(0),
      );
      expect(selected.length, 3);
      expect(selected.every((item) => item.id < 1000), isTrue);
    });

    test('错词模式只取 wrong 池', () {
      final selected = selectCandidates(
        StudyMode.wrongWords,
        _pools(due: 10, wrong: 4, fresh: 10, wrongLimit: 2),
        random: _fixed(0),
      );
      expect(selected.length, 2);
      expect(
        selected.every((item) => item.id >= 1000 && item.id < 2000),
        isTrue,
      );
    });

    test('新词模式只取 fresh 池', () {
      final selected = selectCandidates(
        StudyMode.newWords,
        _pools(due: 10, wrong: 10, fresh: 4, freshLimit: 4),
        random: _fixed(0),
      );
      expect(selected.length, 4);
      expect(selected.every((item) => item.id >= 2000), isTrue);
    });

    test('AI 推荐模式不从这里取题', () {
      expect(
        selectCandidates(
          StudyMode.aiRecommended,
          _pools(due: 5),
          random: _fixed(0),
        ),
        isEmpty,
      );
    });

    test('同一词条不会重复出现', () {
      final shared = _candidate(7);
      final pools = StudyPools(
        due: <StudyCandidate>[shared],
        wrong: <StudyCandidate>[shared],
        fresh: <StudyCandidate>[shared],
        limits: const PoolLimits(due: 10, wrong: 10, fresh: 10),
      );
      final selected = selectCandidates(
        StudyMode.sentenceReview,
        pools,
        random: _fixed(0),
      );
      expect(selected.map((item) => item.id).toSet().length, selected.length);
    });

    test('每日模式抽满配额且不超出候选总数', () {
      final selected = selectCandidates(
        StudyMode.daily,
        _pools(due: 10, wrong: 10, fresh: 10),
        random: _fixed(0.5),
      );
      expect(selected.length, 30);
      expect(selected.map((item) => item.id).toSet().length, 30);
    });

    test('新词占比受软上限约束', () {
      const limit = 30;
      final selected = selectWeightedMixed(
        _pools(due: 20, fresh: 20),
        limit,
        _fixed(0.5),
      );
      final freshCount = selected.where((item) => item.id >= 2000).length;
      final target = (limit * dailyNewWordRatio).ceil();
      expect(selected.length, limit);
      expect(freshCount, lessThanOrEqualTo(target));
    });

    test('软上限是「软」的：复习池耗尽后剩余新词仍会被取走', () {
      // 上限只在「还有得选」时起作用。若复习池已空，硬性停手会让
      // 用户明明还有新词可学却无题可做。
      final selected = selectWeightedMixed(
        _pools(due: 2, fresh: 20),
        10,
        _fixed(0.5),
      );
      expect(selected.length, 10);
      expect(selected.where((item) => item.id >= 2000).length, 8);
    });

    test('每日模式给候选打上任务类型标记', () {
      final selected = selectCandidates(
        StudyMode.daily,
        _pools(due: 5, wrong: 5, fresh: 5),
        random: _fixed(0.5),
      );
      expect(selected.every((item) => item.continuousTaskType != null), isTrue);
    });

    test('交错模式按配比循环取完全部候选', () {
      final selected = selectCandidates(
        StudyMode.listening,
        _pools(due: 10, wrong: 10, fresh: 10),
        random: _fixed(0),
      );
      // 配比 [5,2,2] 每轮 9 题，三轮半取完 30 题。
      expect(selected.length, 30);
      // 第一轮顺序：5 到期 → 2 错词 → 2 新词。
      expect(selected.take(5).every((item) => item.id < 1000), isTrue);
      expect(
        selected
            .skip(5)
            .take(2)
            .every((item) => item.id >= 1000 && item.id < 2000),
        isTrue,
      );
      expect(selected.skip(7).take(2).every((item) => item.id >= 2000), isTrue);
    });

    test('交错模式受各池配额裁剪', () {
      final selected = selectCandidates(
        StudyMode.listening,
        _pools(
          due: 10,
          wrong: 10,
          fresh: 10,
          dueLimit: 3,
          wrongLimit: 1,
          freshLimit: 1,
        ),
        random: _fixed(0),
      );
      // 配额 3/1/1，一轮取完。
      expect(selected.length, 5);
    });

    test('交错模式候选不足时不越界', () {
      final selected = selectCandidates(
        StudyMode.spelling,
        _pools(due: 1),
        random: _fixed(0),
      );
      expect(selected.length, 1);
    });
  });

  group('takeWeightedCandidate', () {
    test('空池返回 null', () {
      expect(
        takeWeightedCandidate(
          <StudyCandidate>[],
          _fixed(0),
          StudyTaskType.review,
        ),
        isNull,
      );
    });

    test('取出后会从池中移除', () {
      final items = <StudyCandidate>[_candidate(1), _candidate(2)];
      takeWeightedCandidate(items, _fixed(0), StudyTaskType.review);
      expect(items.length, 1);
    });

    test('随机值极小时取最靠前的一项', () {
      final items = <StudyCandidate>[
        _candidate(1),
        _candidate(2),
        _candidate(3),
      ];
      final picked = takeWeightedCandidate(
        items,
        _fixed(0),
        StudyTaskType.review,
      );
      expect(picked?.id, 1);
    });

    test('打上调用方指定的任务类型', () {
      final items = <StudyCandidate>[_candidate(1)];
      final picked = takeWeightedCandidate(
        items,
        _fixed(0.5),
        StudyTaskType.wrong,
      );
      expect(picked?.continuousTaskType, StudyTaskType.wrong);
    });
  });

  group('weightedIndex', () {
    test('长度为 1 时恒为 0', () {
      expect(weightedIndex(1, _fixed(0.9), (_) => 1), 0);
    });

    test('随机值落在首项权重区间内时返回 0', () {
      expect(weightedIndex(3, _fixed(0), (_) => 1), 0);
    });

    test('随机值接近 1 时返回最后一项', () {
      expect(weightedIndex(3, _fixed(0.999), (_) => 1), 2);
    });

    test('权重集中时结果跟随权重', () {
      // 第 0 项权重极小、第 1 项极大，随机值 0.5 落在第 1 项区间。
      final index = weightedIndex(2, _fixed(0.5), (i) => i == 0 ? 0.001 : 100);
      expect(index, 1);
    });
  });

  group('fillFromFallback', () {
    test('按需补齐数量', () {
      final fallback = <StudyCandidate>[
        for (var i = 0; i < 10; i += 1) _candidate(i),
      ];
      expect(
        fillFromFallback(
          fallback,
          4,
          _sequence(<double>[0.1, 0.5, 0.9]),
        ).length,
        4,
      );
    });

    test('候选不足时返回全部', () {
      final fallback = <StudyCandidate>[_candidate(1)];
      expect(fillFromFallback(fallback, 5, _fixed(0.5)).length, 1);
    });

    test('需求为 0 时返回空', () {
      final fallback = <StudyCandidate>[_candidate(1)];
      expect(fillFromFallback(fallback, 0, _fixed(0.5)), isEmpty);
    });
  });

  group('boundedCandidateRandom', () {
    test('负值与超界值被夹取', () {
      expect(boundedCandidateRandom(_fixed(-1)), 0);
      expect(boundedCandidateRandom(_fixed(2)), candidateRandomCeiling);
      expect(boundedCandidateRandom(_fixed(0.5)), 0.5);
    });
  });
}
