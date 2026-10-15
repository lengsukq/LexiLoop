/// 设置解析与写回的单元测试。
///
/// 设置是「用户配置」与「默认值」的合并结果，最容易出的问题是
/// 单个坏值让整份配置退回默认、以及写回时丢掉未建模的键。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

void main() {
  group('默认值', () {
    test('空映射解析为全默认', () {
      final settings = appSettingsFromRaw(const <String, Object?>{});
      expect(settings.studyPlan.dailyNewWords, defaultDailyNewWords);
      expect(
        settings.studyPlan.dailyWrongWordLimit,
        defaultDailyWrongWordLimit,
      );
      expect(
        settings.studyPlan.dailyDueReviewLimit,
        defaultDailyDueReviewLimit,
      );
      expect(settings.studyPlan.targetRetentionRate, defaultRetentionRate);
      expect(settings.playback.defaultAccent, Accent.us);
      expect(settings.playback.autoPlayPronunciation, isTrue);
      expect(settings.vocabularyLevel, VocabularyLevel.auto);
      expect(settings.examTargets, isEmpty);
      expect(settings.questionTypeConfig.hasEnabledType, isTrue);
    });

    test('默认题型配置启用全部 8 种题型且权重一致', () {
      for (final type in QuestionType.values) {
        expect(
          QuestionTypeConfig.defaults.isEnabled(type),
          isTrue,
          reason: type.wire,
        );
        expect(
          QuestionTypeConfig.defaults.weightOf(type),
          defaultQuestionTypeWeight.toDouble(),
          reason: type.wire,
        );
      }
    });
  });

  group('数值夹取', () {
    test('超过上限的配额被夹到上限', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': 99999,
        'dailyWrongWordLimit': 99999,
        'dailyDueReviewLimit': 99999,
      });
      expect(settings.studyPlan.dailyNewWords, maxDailyNewWords);
      expect(settings.studyPlan.dailyWrongWordLimit, maxDailyWrongWordLimit);
      expect(settings.studyPlan.dailyDueReviewLimit, maxDailyDueReviewLimit);
    });

    test('负配额被夹到 0', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': -5,
        'dailyWrongWordLimit': -5,
      });
      expect(settings.studyPlan.dailyNewWords, 0);
      expect(settings.studyPlan.dailyWrongWordLimit, 0);
    });

    test('保持率被夹到合法区间', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'targetRetentionRate': 0.1})
            .studyPlan
            .targetRetentionRate,
        minRetentionRate,
      );
      expect(
        appSettingsFromRaw(<String, Object?>{'targetRetentionRate': 5})
            .studyPlan
            .targetRetentionRate,
        maxRetentionRate,
      );
    });

    test('语速被夹到合法区间', () {
      final fast = appSettingsFromRaw(<String, Object?>{
        'wordSpeed': 99,
        'phraseSpeed': 0,
        'sentenceSpeed': 1.5,
      });
      expect(fast.playback.wordSpeed, maxSpeechRate);
      expect(fast.playback.phraseSpeed, minSpeechRate);
      expect(fast.playback.sentenceSpeed, 1.5);
    });

    test('揭示延迟被夹到上限', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'choiceRevealDelaySeconds': 9999})
            .playback
            .choiceRevealDelaySeconds,
        maxChoiceRevealDelaySeconds,
      );
    });

    test('小数配额被四舍五入', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'dailyNewWords': 7.6})
            .studyPlan
            .dailyNewWords,
        8,
      );
    });
  });

  group('类型不符时的兜底', () {
    test('数值字段收到字符串时退回默认', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': 'ten',
        'targetRetentionRate': 'high',
      });
      expect(settings.studyPlan.dailyNewWords, defaultDailyNewWords);
      expect(settings.studyPlan.targetRetentionRate, defaultRetentionRate);
    });

    test('布尔字段收到字符串时退回默认', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'autoPlayPronunciation': 'yes',
        'youdaoEnabled': 1,
      });
      expect(settings.playback.autoPlayPronunciation, isTrue);
      expect(settings.providers.youdaoEnabled, isTrue);
    });

    test('单个键损坏不影响其他键', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': 'bad',
        'dailyWrongWordLimit': 42,
      });
      expect(settings.studyPlan.dailyNewWords, defaultDailyNewWords);
      expect(settings.studyPlan.dailyWrongWordLimit, 42);
    });

    test('口音只接受 US/UK，其他值退回 US', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'defaultAccent': 'UK'})
            .playback
            .defaultAccent,
        Accent.uk,
      );
      expect(
        appSettingsFromRaw(<String, Object?>{'defaultAccent': 'GENERAL'})
            .playback
            .defaultAccent,
        Accent.us,
      );
    });
  });

  group('词汇水平与考试目标', () {
    test('按存储标识解析档位', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'vocabularyLevel': 'CET6'})
            .vocabularyLevel,
        VocabularyLevel.cet6,
      );
    });

    test('未知档位退回 AUTO', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'vocabularyLevel': 'GRE'})
            .vocabularyLevel,
        VocabularyLevel.auto,
      );
    });

    test('考试目标过滤 AUTO 与非法值并去重', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'examTargets': <Object?>['CET4', 'AUTO', 'CET4', 'IELTS', 42, 'GRE'],
      });
      expect(settings.examTargets, <VocabularyLevel>[
        VocabularyLevel.cet4,
        VocabularyLevel.ielts,
      ]);
    });

    test('考试目标不是数组时为空', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'examTargets': 'CET4'})
            .examTargets,
        isEmpty,
      );
    });
  });

  group('题型配置', () {
    test('解析后权重被夹到合法区间', () {
      final config = questionTypeConfigFromJson(<String, Object?>{
        'EN_TO_ZH': <String, Object?>{'enabled': true, 'weight': 999},
        'LETTER_BANK': <String, Object?>{'enabled': true, 'weight': -3},
      });
      expect(
        config.weightOf(QuestionType.enToZh),
        maxQuestionTypeWeight.toDouble(),
      );
      expect(
        config.weightOf(QuestionType.letterBank),
        minQuestionTypeWeight.toDouble(),
      );
    });

    test('全部关闭时整体回退默认', () {
      final config = questionTypeConfigFromJson(<String, Object?>{
        for (final type in QuestionType.values)
          type.wire: <String, Object?>{'enabled': false, 'weight': 5},
      });
      expect(config.hasEnabledType, isTrue);
      for (final type in QuestionType.values) {
        expect(config.isEnabled(type), isTrue, reason: type.wire);
      }
    });

    test('部分启用时保留用户选择', () {
      final config = questionTypeConfigFromJson(<String, Object?>{
        'EN_TO_ZH': <String, Object?>{'enabled': true, 'weight': 3},
        'LETTER_BANK': <String, Object?>{'enabled': false, 'weight': 5},
      });
      expect(config.isEnabled(QuestionType.enToZh), isTrue);
      expect(config.isEnabled(QuestionType.letterBank), isFalse);
      // 未出现在输入里的题型取默认（启用）。
      expect(config.isEnabled(QuestionType.clozeSentence), isTrue);
    });

    test('非映射输入退回默认', () {
      expect(questionTypeConfigFromJson('nope').hasEnabledType, isTrue);
    });

    test('toJson 与 fromJson 往返一致', () {
      final original = questionTypeConfigFromJson(<String, Object?>{
        'EN_TO_ZH': <String, Object?>{'enabled': true, 'weight': 7},
        'LETTER_BANK': <String, Object?>{'enabled': false, 'weight': 2},
      });
      final roundTrip = questionTypeConfigFromJson(original.toJson());
      for (final type in QuestionType.values) {
        expect(
          roundTrip.isEnabled(type),
          original.isEnabled(type),
          reason: type.wire,
        );
        expect(
          roundTrip.weightOf(type),
          original.weightOf(type),
          reason: type.wire,
        );
      }
    });
  });

  group('写回存储', () {
    test('未建模的键被原样保留', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'llmConfig': <String, Object?>{
          'ai': <String, Object?>{'enabled': true},
        },
        'merriamWebsterDictionaryKey': 'secret',
        'dailyNewWords': 5,
      });
      final storage = settings.toStorage();
      expect(storage['llmConfig'], isA<Map<String, Object?>>());
      expect(storage['merriamWebsterDictionaryKey'], 'secret');
      expect(storage['dailyNewWords'], 5);
    });

    test('已建模的键用解析后的值覆盖原始值', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': 99999,
      });
      expect(settings.toStorage()['dailyNewWords'], maxDailyNewWords);
    });

    test('写回内容能再次解析出同样的结果', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'dailyNewWords': 12,
        'targetRetentionRate': 0.85,
        'defaultAccent': 'UK',
        'vocabularyLevel': 'IELTS',
        'examTargets': <Object?>['IELTS', 'TOEFL'],
        'llmConfig': <String, Object?>{'kept': true},
      });
      final reparsed = appSettingsFromRaw(settings.toStorage());
      expect(reparsed.studyPlan.dailyNewWords, 12);
      expect(reparsed.studyPlan.targetRetentionRate, 0.85);
      expect(reparsed.playback.defaultAccent, Accent.uk);
      expect(reparsed.vocabularyLevel, VocabularyLevel.ielts);
      expect(reparsed.examTargets, <VocabularyLevel>[
        VocabularyLevel.ielts,
        VocabularyLevel.toefl,
      ]);
      expect(reparsed.raw['llmConfig'], isA<Map<String, Object?>>());
    });

    test('raw 是只读视图', () {
      final settings = appSettingsFromRaw(<String, Object?>{'a': 1});
      expect(() => settings.raw['b'] = 2, throwsUnsupportedError);
    });
  });

  group('语速取值', () {
    test('按词条类型选语速', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'wordSpeed': 0.8,
        'phraseSpeed': 1,
        'sentenceSpeed': 1.2,
      });
      expect(settings.playback.speedFor(LexicalContentType.word), 0.8);
      expect(settings.playback.speedFor(LexicalContentType.phrase), 1);
      expect(settings.playback.speedFor(LexicalContentType.sentence), 1.2);
    });

    test('类型未知时用单词语速', () {
      final settings = appSettingsFromRaw(<String, Object?>{'wordSpeed': 0.7});
      expect(settings.playback.speedFor(null), 0.7);
    });
  });
}
