/// 每日建议服务测试。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/suggestion_service.dart';

/// 可编程的假 AI 生成器。
class FakeGenerator implements SuggestionAiGenerator {
  new(this.output);

  final Map<String, Object?> output;

  /// 被调用的次数。
  int calls = 0;

  @override
  String get providerId => 'p1';

  @override
  String get model => 'm1';

  @override
  Future<Map<String, Object?>> generate({
    required DailySuggestionMetrics metrics,
    required List<RecommendedStudyItem> candidates,
    required String sourceDateKey,
  }) async {
    calls += 1;
    return output;
  }
}

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late int now;
  late int sourceReviewedAt;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    sourceReviewedAt = DateTime(2026, 2, 28, 20).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord({
    required String term,
    int masteryScore = 0,
    bool isSuspended = false,
    InitializationStatus status = InitializationStatus.ready,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: EntryType.word,
            masteryScore: Value<int>(masteryScore),
            isSuspended: Value<bool>(isSuspended),
            initializationStatus: Value<InitializationStatus>(status),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(
              jsonEncode(<Object?>[
                <String, Object?>{
                  'language': 'zh-CN',
                  'text': '$term 的释义',
                  'partOfSpeech': 'n',
                },
              ]),
            ),
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> insertReview({
    required int index,
    required int wordId,
    required bool isCorrect,
    ReviewRating rating = ReviewRating.again,
    int? durationMs,
  }) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          clientAnswerId: 'answer-$index',
          wordId: wordId,
          reviewedAt: sourceReviewedAt,
          rating: rating,
          questionType: QuestionType.enToZh,
          isCorrect: isCorrect,
          durationMs: Value<int?>(durationMs),
          createdAt: now,
        ),
      );

  group('规则式建议', () {
    test('排序权重：答错更多次的词条排在前面', () async {
      final strong = await insertWord(term: 'strong');
      final weak = await insertWord(term: 'weak');
      await insertReview(index: 1, wordId: weak, isCorrect: false);
      await insertReview(index: 2, wordId: weak, isCorrect: false);
      await insertReview(index: 3, wordId: strong, isCorrect: false);

      final suggestion = await SuggestionService(
        db,
        settings,
      ).generate(now: now);

      expect(suggestion.generator, SuggestionGenerator.ruleBased);
      expect(suggestion.recommendedItems, hasLength(2));
      expect(suggestion.recommendedItems.first.wordId, weak);
      // 每条记录同时是「答错」（120）与「选择忘记」（75）。
      expect(suggestion.recommendedItems.first.score, 2 * 120 + 2 * 75);
      expect(suggestion.recommendedItems.last.score, 120 + 75);
      expect(suggestion.recommendedItems.first.term, 'weak');
      expect(suggestion.recommendedItems.first.definition, 'weak 的释义');
      expect(suggestion.metrics.reviewCount, 3);
      expect(suggestion.metrics.correctCount, 0);
      expect(suggestion.metrics.accuracy, 0);
    });

    test('没有作答记录时给出恢复节奏的文案并落库', () async {
      await insertWord(term: 'alpha');
      final suggestion = await SuggestionService(
        db,
        settings,
      ).generate(now: now);
      expect(suggestion.metrics.reviewCount, 0);
      expect(suggestion.headline, '今天先恢复学习节奏');
      expect(suggestion.recommendedItems, isNotEmpty);

      final rows = await db
          .customSelect('SELECT COUNT(*) AS c FROM daily_ai_suggestions')
          .getSingle();
      expect(rows.read<int>('c'), 1);
    });

    test('today 读取当天缓存，不重复生成', () async {
      await insertWord(term: 'alpha');
      final service = SuggestionService(db, settings);
      final first = await service.today(now: now);
      final second = await service.today(now: now + 60000);
      expect(second!.generatedAt, first!.generatedAt);
      expect(second.dateKey, dateKey(now));
      expect(second.sourceDateKey, previousDateKey(now));
    });

    test('暂停的词条不会出现在推荐里', () async {
      final active = await insertWord(term: 'active');
      final paused = await insertWord(term: 'paused', isSuspended: true);
      await insertReview(index: 1, wordId: active, isCorrect: false);
      await insertReview(index: 2, wordId: paused, isCorrect: false);
      final suggestion = await SuggestionService(
        db,
        settings,
      ).generate(now: now);
      expect(
        suggestion.recommendedItems.map((item) => item.wordId),
        isNot(contains(paused)),
      );
    });
  });

  group('AI 生成', () {
    test('质量分过低时整份丢弃并回退规则式', () async {
      final wordId = await insertWord(term: 'weak');
      await insertReview(index: 1, wordId: wordId, isCorrect: false);
      final generator = FakeGenerator(<String, Object?>{
        'headline': '',
        'summary': '',
        'strengths': <Object?>[],
        'risks': <Object?>[],
        'actions': <Object?>[],
        'recommended': <Object?>[],
      });

      final suggestion = await SuggestionService(
        db,
        settings,
        generator,
      ).generate(now: now);

      expect(generator.calls, 1);
      expect(suggestion.generator, SuggestionGenerator.ruleBased);
      expect(suggestion.generationWarning, contains('质量评分过低'));
      expect(suggestion.headline, isNot(isEmpty));
      expect(suggestion.providerId, isNull);
    });

    test('质量达标时采用 AI 文案与推荐顺序', () async {
      final first = await insertWord(term: 'alpha');
      final second = await insertWord(term: 'beta');
      await insertReview(index: 1, wordId: first, isCorrect: false);
      await insertReview(index: 2, wordId: second, isCorrect: false);
      final generator = FakeGenerator(<String, Object?>{
        'headline': 'AI 标题',
        'summary': 'AI 总结',
        'strengths': <Object?>['亮点一'],
        'risks': <Object?>['风险一'],
        'actions': <Object?>['行动一', '行动二'],
        'recommended': <Object?>[
          <String, Object?>{'wordId': second, 'reason': 'AI 指定优先'},
        ],
      });

      final suggestion = await SuggestionService(
        db,
        settings,
        generator,
      ).generate(now: now);

      expect(suggestion.generator, SuggestionGenerator.ai);
      expect(suggestion.headline, 'AI 标题');
      expect(suggestion.actions, <String>['行动一', '行动二']);
      expect(suggestion.providerId, 'p1');
      expect(suggestion.model, 'm1');
      expect(suggestion.generationWarning, isNull);
      // AI 指定的词条排在最前，其余按分数补齐。
      expect(suggestion.recommendedItems.first.wordId, second);
      expect(suggestion.recommendedItems.first.reason, 'AI 指定优先');
      expect(suggestion.recommendedItems, hasLength(2));
    });

    test('aiSuggestionQualityScore 只认候选池内的 wordId', () {
      final candidates = <RecommendedStudyItem>[
        const RecommendedStudyItem(
          wordId: 1,
          term: 'alpha',
          reason: 'r',
          questionType: QuestionType.enToZh,
          score: 1,
        ),
      ];
      final complete = <String, Object?>{
        'headline': 'h',
        'summary': 's',
        'strengths': <Object?>[],
        'risks': <Object?>['r'],
        'actions': <Object?>['a', 'b'],
        'recommended': <Object?>[
          <String, Object?>{'wordId': 1, 'reason': 'ok'},
        ],
      };
      expect(
        aiSuggestionQualityScore(complete, candidates),
        greaterThanOrEqualTo(aiQualityScoreThreshold),
      );
      // wordId 不在候选池内 → 不加分。
      final bogus = <String, Object?>{
        ...complete,
        'recommended': <Object?>[
          <String, Object?>{'wordId': 999, 'reason': 'x'},
        ],
      };
      expect(
        aiSuggestionQualityScore(bogus, candidates),
        lessThan(aiSuggestionQualityScore(complete, candidates)),
      );
      expect(aiSuggestionQualityScore(<String, Object?>{}, candidates), 0);
    });
  });
}
