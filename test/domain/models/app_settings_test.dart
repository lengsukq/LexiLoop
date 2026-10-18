/// 设置解析与写回的单元测试。
///
/// 设置是「用户配置」与「默认值」的合并结果，最容易出的问题是
/// 单个坏值让整份配置退回默认、以及写回时丢掉未建模的键。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

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

  group('AI 重试遍数', () {
    test('类型化字段写回存储', () {
      final settings = appSettingsFromRaw(<String, Object?>{'aiRetryCount': 3});
      expect(settings.studyPlan.aiRetryCount, 3);
      expect(settings.toStorage()['aiRetryCount'], 3);
    });

    test('超出 0–5 的值被夹回区间', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'aiRetryCount': -3})
            .studyPlan
            .aiRetryCount,
        aiRetryCountFloor,
      );
      expect(
        appSettingsFromRaw(<String, Object?>{'aiRetryCount': 99})
            .studyPlan
            .aiRetryCount,
        aiRetryCountCeiling,
      );
    });

    test('小数被四舍五入后再夹取', () {
      expect(
        appSettingsFromRaw(<String, Object?>{'aiRetryCount': 2.4})
            .studyPlan
            .aiRetryCount,
        2,
      );
      expect(
        appSettingsFromRaw(<String, Object?>{'aiRetryCount': 7.6})
            .studyPlan
            .aiRetryCount,
        aiRetryCountCeiling,
      );
    });

    test('缺键与非数值退回默认值', () {
      expect(
        appSettingsFromRaw(const <String, Object?>{}).studyPlan.aiRetryCount,
        aiRetryCountDefault,
      );
      expect(
        appSettingsFromRaw(<String, Object?>{'aiRetryCount': '三次'})
            .studyPlan
            .aiRetryCount,
        aiRetryCountDefault,
      );
    });

    test('写入后真的到达 LlmAiConfig.retryCount（端到端）', () {
      final storage = appSettingsFromRaw(<String, Object?>{'aiRetryCount': 3})
          .toStorage();

      expect(storage[aiRetryCountSettingsKey], 3);
      expect(llmConfigFromSettings(storage).ai.retryCount, 3);
    });

    test('读的是设置顶层，而不是 llmConfig.ai 下的同名字段', () {
      // 旧版 `modules/settings/service.ts:77` 把它定义在设置对象顶层。
      // 本版曾从 `llmConfig.ai` 下读，用户改了设置也不生效——这里钉住层级。
      final storage = appSettingsFromRaw(<String, Object?>{
        'aiRetryCount': 3,
        'llmConfig': <String, Object?>{
          'ai': <String, Object?>{'enabled': true, 'retryCount': 5},
        },
      }).toStorage();

      expect(llmConfigFromSettings(storage).ai.retryCount, 3);
    });

    test('与 core/constants.dart 中的同名常量取值一致', () {
      // 两个文件里各有一份（后者按其文件头注释应在后续提交整体上移到 core）。
      // 一旦有人只改一处，这里会红。
      expect(aiRetryCountCeiling, maxAiRetryCount);
      expect(aiRetryCountDefault, defaultAiRetryCount);
    });
  });

  group('权重预设', () {
    test('均衡：8 种题型全部为默认权重', () {
      final weights = _preset('balanced').weights;
      expect(weights.length, QuestionType.values.length);
      for (final type in QuestionType.values) {
        expect(weights[type], defaultQuestionTypeWeight, reason: type.wire);
      }
    });

    test('记忆为主：英选中 8 / 中选英 7 / 英译中 5 / 中译英拼写 4', () {
      expect(_preset('recallFirst').weights, <QuestionType, int>{
        QuestionType.enToZhChoice: 8,
        QuestionType.zhToEnChoice: 7,
        QuestionType.enToZh: 5,
        QuestionType.zhToEnSpelling: 4,
      });
    });

    test('拼写强化：拼写 9 / 字母拼词 8 / 例句填空 7', () {
      expect(_preset('spellingFocus').weights, <QuestionType, int>{
        QuestionType.zhToEnSpelling: 9,
        QuestionType.letterBank: 8,
        QuestionType.clozeSentence: 7,
      });
    });

    test('听力强化：两种听力题型各 9', () {
      expect(_preset('listeningFocus').weights, <QuestionType, int>{
        QuestionType.listeningChoice: 9,
        QuestionType.listeningSpelling: 9,
      });
    });

    test('预设只覆盖列出的题型，其余保持用户当前值', () {
      final base = QuestionTypeConfig.defaults.withWeights({
        QuestionType.enToZh: 2,
        QuestionType.letterBank: 9,
      });

      final applied = _preset('spellingFocus').applyTo(base);

      expect(applied.weightOf(QuestionType.zhToEnSpelling), 9);
      expect(applied.weightOf(QuestionType.letterBank), 8);
      expect(applied.weightOf(QuestionType.clozeSentence), 7);
      expect(applied.weightOf(QuestionType.enToZh), 2);
      expect(applied.weightOf(QuestionType.listeningChoice), 5);
    });

    test('预设不改动任何开关状态', () {
      final base = QuestionTypeConfig.defaults.withWeights({
        QuestionType.letterBank: 3,
      });

      final applied = _preset('listeningFocus').applyTo(base);

      for (final type in QuestionType.values) {
        expect(applied.isEnabled(type), isTrue, reason: type.wire);
      }
    });

    test('应用预设后再改一个题型，其余保持预设值', () {
      final applied = _preset('spellingFocus')
          .applyTo(QuestionTypeConfig.defaults);

      final edited = applied.withWeights({QuestionType.letterBank: 2});

      expect(edited.weightOf(QuestionType.letterBank), 2);
      expect(edited.weightOf(QuestionType.zhToEnSpelling), 9);
      expect(edited.weightOf(QuestionType.clozeSentence), 7);
    });

    test('defaults 就是「重置均衡」的基线', () {
      final scrambled = _preset('listeningFocus')
          .applyTo(QuestionTypeConfig.defaults)
          .withWeights({QuestionType.clozeSentence: 1});

      expect(scrambled.weightOf(QuestionType.listeningChoice), 9);
      expect(QuestionTypeConfig.defaults.weightOf(QuestionType.enToZh), 5);
      for (final type in QuestionType.values) {
        expect(
          QuestionTypeConfig.defaults.isEnabled(type),
          isTrue,
          reason: type.wire,
        );
      }
    });
  });

  group('权重占比', () {
    test('各题型占比合计为 100%', () {
      for (final preset in questionTypeWeightPresets) {
        final config = preset.applyTo(QuestionTypeConfig.defaults);
        expect(
          config.sharePercents().reduce((a, b) => a + b),
          closeTo(questionTypePercentScale, 1e-9),
          reason: preset.id,
        );
      }
    });

    test('默认配置下每种题型各占八分之一', () {
      final shares = QuestionTypeConfig.defaults.sharePercents();
      for (final share in shares) {
        expect(share, closeTo(questionTypePercentScale / 8, 1e-9));
      }
    });

    test('关闭的题型占比为 0，且分母只算启用项', () {
      final disabled = QuestionTypeConfig(<QuestionType, QuestionTypeSetting>{
        for (final type in QuestionType.values)
          type: QuestionTypeSetting(
            enabled: type != QuestionType.letterBank,
            weight: defaultQuestionTypeWeight,
          ),
      });

      expect(disabled.totalEnabledWeight, 35);
      expect(disabled.sharePercentOf(QuestionType.letterBank), 0);
      expect(
        disabled.sharePercents().reduce((a, b) => a + b),
        closeTo(questionTypePercentScale, 1e-9),
      );
    });

    test('权重更高的题型占比更大', () {
      final config = _preset('listeningFocus')
          .applyTo(QuestionTypeConfig.defaults);
      expect(
        config.sharePercentOf(QuestionType.listeningChoice),
        greaterThan(config.sharePercentOf(QuestionType.enToZh)),
      );
    });
  });

  group('外观设置', () {
    test('默认跟随系统、薄荷主色与靛蓝次色', () {
      final settings = appSettingsFromRaw(const <String, Object?>{});
      expect(settings.appearance.mode, AppThemeMode.system);
      expect(settings.appearance.primaryColor, defaultThemePrimaryColor);
      expect(settings.appearance.secondaryColor, defaultThemeSecondaryColor);
    });

    test('解析模式、主色与次色', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'themeMode': 'dark',
        'themePrimaryColor': 0xFF0A84FF,
        'themeSecondaryColor': 0xFFFF2D55,
      });
      expect(settings.appearance.mode, AppThemeMode.dark);
      expect(settings.appearance.primaryColor, 0xFF0A84FF);
      expect(settings.appearance.secondaryColor, 0xFFFF2D55);
    });

    test('未知模式回跟随系统，非法颜色回默认值', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'themeMode': 'sepia',
        'themePrimaryColor': 'blue',
        'themeSecondaryColor': -1,
      });
      expect(settings.appearance.mode, AppThemeMode.system);
      expect(settings.appearance.primaryColor, defaultThemePrimaryColor);
      expect(settings.appearance.secondaryColor, defaultThemeSecondaryColor);
    });

    test('颜色强制不透明，且往返存储不变', () {
      final settings = appSettingsFromRaw(<String, Object?>{
        'themePrimaryColor': 0x000A84FF,
      });
      expect(settings.appearance.primaryColor, 0xFF0A84FF);
      final reparsed = appSettingsFromRaw(settings.toStorage());
      expect(reparsed.appearance.primaryColor, 0xFF0A84FF);
      expect(reparsed.appearance.mode, AppThemeMode.system);
    });
  });
}

/// 按标识取预设；找不到直接失败——测试里写错 id 不该静默跳过。
QuestionTypeWeightPreset _preset(String id) {
  for (final preset in questionTypeWeightPresets) {
    if (preset.id == id) return preset;
  }
  throw StateError('未找到权重预设：$id');
}
