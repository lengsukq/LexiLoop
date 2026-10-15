/// 应用设置的类型化视图。
///
/// **存储形态**：`settings` 表是 key → value_json 的键值表（沿用旧版），
/// 每项设置一行。这里提供的是**类型化视图**，不是存储结构。
///
/// **为什么按组拆分**：[AppSettings] 直接摊平会有 19 个字段，任何一处
/// 构造、拷贝或解析都会长到无法阅读。分组边界与旧版设置页的 tab 一致
/// （学习计划 / 播放 / 数据源），因此这个划分不是为拆而拆。
///
/// **为什么保留 [AppSettings.raw]**：LLM provider 配置等尚未建模的键
/// 必须能原样写回，否则用户在 AI 设置做完之前改一次学习设置就会把
/// AI 配置清空。因此解析是「读已知键 + 保留其余」，写回是
/// 「已知键覆盖 + 其余原样」。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';

/// 词汇水平档位。
enum VocabularyLevel {
  /// 不限定。
  auto('AUTO'),

  /// 大学英语四级。
  cet4('CET4'),

  /// 大学英语六级。
  cet6('CET6'),

  /// 考研。
  ky('KY'),

  /// 雅思。
  ielts('IELTS'),

  /// 托福。
  toefl('TOEFL');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值返回 [VocabularyLevel.auto]。
  static VocabularyLevel fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return VocabularyLevel.auto;
  }
}

/// 单个题型的开关与权重。
class QuestionTypeSetting {
  /// 以各字段构造。
  const new({required this.enabled, required this.weight});

  /// 是否启用。
  final bool enabled;

  /// 抽题权重（[minQuestionTypeWeight]–[maxQuestionTypeWeight]）。
  final int weight;
}

/// 未配置题型的兜底项。
const QuestionTypeSetting defaultQuestionTypeSetting = QuestionTypeSetting(
  enabled: true,
  weight: defaultQuestionTypeWeight,
);

/// 题型配置：每个题型的开关与权重。
///
/// 用不可变包装而非裸 `Map`，是为了让「至少启用一种题型」这条不变式
/// 只有一个入口可以破坏（[normalized]）。
class QuestionTypeConfig {
  /// 以映射构造（缺失的题型取默认值）。
  const new(this._entries);

  final Map<QuestionType, QuestionTypeSetting> _entries;

  /// 默认配置：全部启用，权重相同。
  static const QuestionTypeConfig defaults = QuestionTypeConfig(
    <QuestionType, QuestionTypeSetting>{
      QuestionType.enToZh: defaultQuestionTypeSetting,
      QuestionType.enToZhChoice: defaultQuestionTypeSetting,
      QuestionType.zhToEnChoice: defaultQuestionTypeSetting,
      QuestionType.zhToEnSpelling: defaultQuestionTypeSetting,
      QuestionType.listeningSpelling: defaultQuestionTypeSetting,
      QuestionType.clozeSentence: defaultQuestionTypeSetting,
      QuestionType.listeningChoice: defaultQuestionTypeSetting,
      QuestionType.letterBank: defaultQuestionTypeSetting,
    },
  );

  /// 该题型是否启用（未配置时取默认项）。
  bool isEnabled(QuestionType type) => _settingOf(type).enabled;

  /// 该题型的权重（未配置时取默认值）。
  double weightOf(QuestionType type) => _settingOf(type).weight.toDouble();

  /// 是否存在至少一种启用的题型。
  bool get hasEnabledType => _entries.values.any((entry) => entry.enabled);

  /// 启用题型的权重之和。
  ///
  /// 抽题只在启用的题型之间按权重分配（对应旧版
  /// `question-type-settings.tsx` 里 `totalWeight` 的算法），所以占比的分母
  /// 是启用项之和而不是全部项之和——关掉一种题型必须让它剩下的分母重新归一。
  int get totalEnabledWeight {
    var total = 0;
    for (final type in QuestionType.values) {
      if (isEnabled(type)) total += _settingOf(type).weight;
    }
    return total;
  }

  /// 该题型占已启用总权重的百分比；未启用或没有启用项时为 0。
  double sharePercentOf(QuestionType type) {
    final total = totalEnabledWeight;
    if (total <= 0 || !isEnabled(type)) return 0;
    return weightOf(type) / total * questionTypePercentScale;
  }

  /// 全部题型的权重占比（按 [QuestionType.values] 顺序，未启用记 0）。
  ///
  /// 只要存在启用的题型，合计就是 [questionTypePercentScale]——界面用它画 100% 占比条，
  /// 「各段之和」与「权重之和」必须保持同一口径，否则色条会溢出或留白。
  List<double> sharePercents() => <double>[
    for (final type in QuestionType.values) sharePercentOf(type),
  ];

  /// 叠加一组权重覆盖：列出的题型换权重，其余题型与所有开关原样保留。
  QuestionTypeConfig withWeights(Map<QuestionType, int> weights) {
    final result = <QuestionType, QuestionTypeSetting>{};
    for (final type in QuestionType.values) {
      final entry = _settingOf(type);
      result[type] = QuestionTypeSetting(
        enabled: entry.enabled,
        weight: weights[type] ?? entry.weight,
      );
    }
    return QuestionTypeConfig(result);
  }

  /// 收敛到合法配置：权重夹到合法区间，且保证至少启用一种题型。
  ///
  /// 全部关闭时整体回退到 [defaults]——旧版在 zod 层做同样的兜底，
  /// 否则会出现「抽不出任何题型」的空白会话。
  QuestionTypeConfig get normalized {
    final result = <QuestionType, QuestionTypeSetting>{};
    for (final type in QuestionType.values) {
      final entry = _settingOf(type);
      result[type] = QuestionTypeSetting(
        enabled: entry.enabled,
        weight: entry.weight.clamp(
          minQuestionTypeWeight,
          maxQuestionTypeWeight,
        ),
      );
    }
    final normalized = QuestionTypeConfig(result);
    return normalized.hasEnabledType ? normalized : defaults;
  }

  /// 取单个题型的配置项；未配置时取 [defaultQuestionTypeSetting]。
  ///
  /// 收敛成一处是因为「未配置」在这八个方法里出现了七次，
  /// 每处各写一遍兜底迟早会漏改一处。
  QuestionTypeSetting _settingOf(QuestionType type) =>
      _entries[type] ?? defaultQuestionTypeSetting;

  /// 转回可 JSON 序列化的映射。
  Map<String, Object?> toJson() => <String, Object?>{
    for (final entry in _entries.entries)
      entry.key.wire: <String, Object?>{
        'enabled': entry.value.enabled,
        'weight': entry.value.weight,
      },
  };
}

/// 从 JSON 值解析题型配置；结构不符时取默认配置。
QuestionTypeConfig questionTypeConfigFromJson(Object? value) {
  if (value is! Map) return QuestionTypeConfig.defaults;
  final entries = <QuestionType, QuestionTypeSetting>{};
  for (final type in QuestionType.values) {
    final raw = value[type.wire];
    if (raw is! Map) continue;
    final enabled = raw['enabled'];
    final weight = raw['weight'];
    entries[type] = QuestionTypeSetting(
      enabled: enabled is bool ? enabled : defaultQuestionTypeSetting.enabled,
      weight: weight is num
          ? weight.round().clamp(minQuestionTypeWeight, maxQuestionTypeWeight)
          : defaultQuestionTypeSetting.weight,
    );
  }
  return QuestionTypeConfig(entries).normalized;
}

/// 题型权重预设：一组「题型 → 目标权重」。
///
/// **权重值逐条取自旧版**
/// `src/app/(main)/settings/components/question-type-settings.tsx:31-36` 的 `PRESETS`，
/// 对应的数值常量在 `core/constants.dart` 中具名。
///
/// **预设只覆盖列出的题型**：与旧版 `applyPreset` 一致，用户手动调过的
/// 其它题型不该被「拼写强化」顺手抹平；开关状态一律保留。
class QuestionTypeWeightPreset {
  /// 以标识、文案与目标权重构造。
  const new({required this.id, required this.label, required this.weights});

  /// 稳定标识（界面 Key 与测试定位用，不随文案变化）。
  final String id;

  /// 界面文案。
  final String label;

  /// 目标权重；未列出的题型保持当前值。
  final Map<QuestionType, int> weights;

  /// 把预设叠加到 [base] 上，得到可直接写回的新配置。
  QuestionTypeConfig applyTo(QuestionTypeConfig base) =>
      base.withWeights(weights);
}

/// 全部权重预设，按界面展示顺序排列。
const List<QuestionTypeWeightPreset> questionTypeWeightPresets =
    <QuestionTypeWeightPreset>[
      QuestionTypeWeightPreset(
        id: 'balanced',
        label: '均衡',
        weights: <QuestionType, int>{
          QuestionType.enToZh: defaultQuestionTypeWeight,
          QuestionType.enToZhChoice: defaultQuestionTypeWeight,
          QuestionType.zhToEnChoice: defaultQuestionTypeWeight,
          QuestionType.zhToEnSpelling: defaultQuestionTypeWeight,
          QuestionType.listeningSpelling: defaultQuestionTypeWeight,
          QuestionType.clozeSentence: defaultQuestionTypeWeight,
          QuestionType.listeningChoice: defaultQuestionTypeWeight,
          QuestionType.letterBank: defaultQuestionTypeWeight,
        },
      ),
      QuestionTypeWeightPreset(
        id: 'recallFirst',
        label: '记忆为主',
        weights: <QuestionType, int>{
          QuestionType.enToZhChoice: recallFirstChoiceWeight,
          QuestionType.zhToEnChoice: recallFirstTranslateWeight,
          QuestionType.enToZh: defaultQuestionTypeWeight,
          QuestionType.zhToEnSpelling: recallFirstSpellingWeight,
        },
      ),
      QuestionTypeWeightPreset(
        id: 'spellingFocus',
        label: '拼写强化',
        weights: <QuestionType, int>{
          QuestionType.zhToEnSpelling: spellingFocusSpellWeight,
          QuestionType.letterBank: spellingFocusLetterBankWeight,
          QuestionType.clozeSentence: spellingFocusClozeWeight,
        },
      ),
      QuestionTypeWeightPreset(
        id: 'listeningFocus',
        label: '听力强化',
        weights: <QuestionType, int>{
          QuestionType.listeningChoice: listeningFocusWeight,
          QuestionType.listeningSpelling: listeningFocusWeight,
        },
      ),
    ];

/// 学习计划设置。
class StudyPlanSettings {
  /// 以各字段构造。
  const new({
    required this.dailyNewWords,
    required this.dailyWrongWordLimit,
    required this.dailyDueReviewLimit,
    required this.targetRetentionRate,
    required this.aiRetryCount,
  });

  /// 每日新词配额。
  final int dailyNewWords;

  /// 每日错词配额。
  final int dailyWrongWordLimit;

  /// 每日到期复习配额。
  final int dailyDueReviewLimit;

  /// 目标记忆保持率（[minRetentionRate]–[maxRetentionRate]）。
  final double targetRetentionRate;

  /// AI 重试遍数（[aiRetryCountFloor]–[aiRetryCountCeiling]）。
  ///
  /// **为什么放在学习计划分组**：旧版把它和配额放在同一张卡片里
  /// （`study-plan-settings.tsx:29`），用户的心智模型是「这套学习流程要花
  /// 多少 AI 调用」。但它的读取方是 LLM 客户端而不是任何队列逻辑。
  final int aiRetryCount;

  /// 默认值。
  static const StudyPlanSettings defaults = StudyPlanSettings(
    dailyNewWords: defaultDailyNewWords,
    dailyWrongWordLimit: defaultDailyWrongWordLimit,
    dailyDueReviewLimit: defaultDailyDueReviewLimit,
    targetRetentionRate: defaultRetentionRate,
    aiRetryCount: aiRetryCountDefault,
  );

  /// 转回存储键值。
  Map<String, Object?> toStorage() => <String, Object?>{
    'dailyNewWords': dailyNewWords,
    'dailyWrongWordLimit': dailyWrongWordLimit,
    'dailyDueReviewLimit': dailyDueReviewLimit,
    'targetRetentionRate': targetRetentionRate,
    'aiRetryCount': aiRetryCount,
  };
}

/// 播放设置。
class PlaybackSettings {
  /// 以各字段构造。
  const new({
    required this.choiceRevealDelaySeconds,
    required this.defaultAccent,
    required this.wordSpeed,
    required this.phraseSpeed,
    required this.sentenceSpeed,
    required this.autoPlayPronunciation,
    this.humanAudioEnabled = true,
  });

  /// 选择题揭示答案前的延迟（秒）。
  final int choiceRevealDelaySeconds;

  /// 默认发音口音。
  final Accent defaultAccent;

  /// 单词朗读语速。
  final double wordSpeed;

  /// 短语朗读语速。
  final double phraseSpeed;

  /// 句子朗读语速。
  final double sentenceSpeed;

  /// 是否自动朗读发音。
  final bool autoPlayPronunciation;

  /// 是否优先播放词典的真人录音（mp3）。
  ///
  /// 关掉它即「只用系统朗读」：真人录音依赖联网与第三方站点，站点不可用
  /// 或用户不愿为一次点按付一次请求时，需要有一个不必改代码的开关。
  /// 默认开启——真人录音相对系统朗读是明确的音质提升。
  final bool humanAudioEnabled;

  /// 默认值。
  static const PlaybackSettings defaults = PlaybackSettings(
    choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
    defaultAccent: Accent.us,
    wordSpeed: defaultSpeechRate,
    phraseSpeed: defaultSpeechRate,
    sentenceSpeed: defaultSpeechRate,
    autoPlayPronunciation: true,
  );

  /// 按词条类型取语速。
  double speedFor(LexicalContentType? type) => switch (type) {
    LexicalContentType.sentence => sentenceSpeed,
    LexicalContentType.phrase => phraseSpeed,
    _ => wordSpeed,
  };

  /// 转回存储键值。
  Map<String, Object?> toStorage() => <String, Object?>{
    'choiceRevealDelaySeconds': choiceRevealDelaySeconds,
    'defaultAccent': defaultAccent.wire,
    'wordSpeed': wordSpeed,
    'phraseSpeed': phraseSpeed,
    'sentenceSpeed': sentenceSpeed,
    'autoPlayPronunciation': autoPlayPronunciation,
    'humanAudioEnabled': humanAudioEnabled,
  };
}

/// 数据源开关。
class ProviderSettings {
  /// 以各字段构造。
  const new({
    required this.dictionaryApiEnabled,
    required this.myMemoryEnabled,
    required this.merriamWebsterEnabled,
    required this.youdaoEnabled,
    required this.icibaEnabled,
  });

  /// 是否启用 dictionaryapi.dev。
  final bool dictionaryApiEnabled;

  /// 是否启用 MyMemory 翻译。
  final bool myMemoryEnabled;

  /// 是否启用 Merriam-Webster。
  final bool merriamWebsterEnabled;

  /// 是否启用有道。
  final bool youdaoEnabled;

  /// 是否启用爱词霸。
  final bool icibaEnabled;

  /// 默认值。
  static const ProviderSettings defaults = ProviderSettings(
    dictionaryApiEnabled: true,
    myMemoryEnabled: true,
    merriamWebsterEnabled: false,
    youdaoEnabled: true,
    icibaEnabled: true,
  );

  /// 转回存储键值。
  Map<String, Object?> toStorage() => <String, Object?>{
    'dictionaryApiEnabled': dictionaryApiEnabled,
    'myMemoryEnabled': myMemoryEnabled,
    'merriamWebsterEnabled': merriamWebsterEnabled,
    'youdaoEnabled': youdaoEnabled,
    'icibaEnabled': icibaEnabled,
  };
}

/// 应用设置的类型化视图。
class AppSettings {
  /// 以各字段构造。
  const new({
    required this.raw,
    required this.studyPlan,
    required this.playback,
    required this.providers,
    required this.vocabularyLevel,
    required this.examTargets,
    required this.questionTypeConfig,
  });

  /// 存储层的原始键值（含未建模的键，写回时必须原样保留）。
  final Map<String, Object?> raw;

  /// 学习计划设置。
  final StudyPlanSettings studyPlan;

  /// 播放设置。
  final PlaybackSettings playback;

  /// 数据源开关。
  final ProviderSettings providers;

  /// 词汇水平档位。
  final VocabularyLevel vocabularyLevel;

  /// 考试目标（可多选）。
  final List<VocabularyLevel> examTargets;

  /// 题型配置。
  final QuestionTypeConfig questionTypeConfig;

  /// 默认设置（无任何用户配置时）。
  static const AppSettings defaults = AppSettings(
    raw: <String, Object?>{},
    studyPlan: StudyPlanSettings.defaults,
    playback: PlaybackSettings.defaults,
    providers: ProviderSettings.defaults,
    vocabularyLevel: VocabularyLevel.auto,
    examTargets: <VocabularyLevel>[],
    questionTypeConfig: QuestionTypeConfig.defaults,
  );

  /// 合并为可写回存储的键值映射。
  ///
  /// 未建模的键从 [raw] 原样带出，避免保存时丢字段。
  Map<String, Object?> toStorage() => <String, Object?>{
    ...raw,
    ...studyPlan.toStorage(),
    ...playback.toStorage(),
    ...providers.toStorage(),
    'vocabularyLevel': vocabularyLevel.wire,
    'examTargets': examTargets.map((level) => level.wire).toList(),
    'questionTypeConfig': questionTypeConfig.toJson(),
  };
}

/// 从存储层的键值映射解析设置。
///
/// 每一项都独立兜底：单个键损坏不应让整份设置退回默认值。
AppSettings appSettingsFromRaw(Map<String, Object?> raw) {
  final reader = _SettingsReader(raw);
  return AppSettings(
    raw: Map<String, Object?>.unmodifiable(raw),
    studyPlan: _parseStudyPlan(reader),
    playback: _parsePlayback(reader),
    providers: _parseProviders(reader),
    vocabularyLevel: VocabularyLevel.fromWire(
      raw['vocabularyLevel'] as String?,
    ),
    examTargets: _examTargets(raw['examTargets']),
    questionTypeConfig: questionTypeConfigFromJson(raw['questionTypeConfig']),
  );
}

StudyPlanSettings _parseStudyPlan(_SettingsReader reader) {
  const fallback = StudyPlanSettings.defaults;
  return StudyPlanSettings(
    dailyNewWords: reader.intValue(
      'dailyNewWords',
      fallback.dailyNewWords,
      min: 0,
      max: maxDailyNewWords,
    ),
    dailyWrongWordLimit: reader.intValue(
      'dailyWrongWordLimit',
      fallback.dailyWrongWordLimit,
      min: 0,
      max: maxDailyWrongWordLimit,
    ),
    dailyDueReviewLimit: reader.intValue(
      'dailyDueReviewLimit',
      fallback.dailyDueReviewLimit,
      min: 1,
      max: maxDailyDueReviewLimit,
    ),
    targetRetentionRate: reader.doubleValue(
      'targetRetentionRate',
      fallback.targetRetentionRate,
      min: minRetentionRate,
      max: maxRetentionRate,
    ),
    aiRetryCount: reader.intValue(
      'aiRetryCount',
      fallback.aiRetryCount,
      min: aiRetryCountFloor,
      max: aiRetryCountCeiling,
    ),
  );
}

PlaybackSettings _parsePlayback(_SettingsReader reader) {
  const fallback = PlaybackSettings.defaults;
  return PlaybackSettings(
    choiceRevealDelaySeconds: reader.intValue(
      'choiceRevealDelaySeconds',
      fallback.choiceRevealDelaySeconds,
      min: 0,
      max: maxChoiceRevealDelaySeconds,
    ),
    defaultAccent: reader.accent(),
    wordSpeed: reader.speechRate('wordSpeed'),
    phraseSpeed: reader.speechRate('phraseSpeed'),
    sentenceSpeed: reader.speechRate('sentenceSpeed'),
    autoPlayPronunciation: reader.boolValue(
      'autoPlayPronunciation',
      fallback: fallback.autoPlayPronunciation,
    ),
    humanAudioEnabled: reader.boolValue(
      'humanAudioEnabled',
      fallback: fallback.humanAudioEnabled,
    ),
  );
}

ProviderSettings _parseProviders(_SettingsReader reader) {
  const fallback = ProviderSettings.defaults;
  return ProviderSettings(
    dictionaryApiEnabled: reader.boolValue(
      'dictionaryApiEnabled',
      fallback: fallback.dictionaryApiEnabled,
    ),
    myMemoryEnabled: reader.boolValue(
      'myMemoryEnabled',
      fallback: fallback.myMemoryEnabled,
    ),
    merriamWebsterEnabled: reader.boolValue(
      'merriamWebsterEnabled',
      fallback: fallback.merriamWebsterEnabled,
    ),
    youdaoEnabled: reader.boolValue(
      'youdaoEnabled',
      fallback: fallback.youdaoEnabled,
    ),
    icibaEnabled: reader.boolValue(
      'icibaEnabled',
      fallback: fallback.icibaEnabled,
    ),
  );
}

/// 带类型兜底的设置读取器。
///
/// 存在的意义是把「取一个键、检查类型、夹到区间、否则用默认值」这套
/// 重复十余次的模式收敛到一处。
class _SettingsReader {
  const new(this._raw);

  final Map<String, Object?> _raw;

  int intValue(String key, int fallback, {required int min, required int max}) {
    final value = _raw[key];
    return value is num ? value.round().clamp(min, max) : fallback;
  }

  double doubleValue(
    String key,
    double fallback, {
    required double min,
    required double max,
  }) {
    final value = _raw[key];
    return value is num ? value.toDouble().clamp(min, max) : fallback;
  }

  bool boolValue(String key, {required bool fallback}) {
    final value = _raw[key];
    return value is bool ? value : fallback;
  }

  /// 朗读语速：三种粒度共用同一合法区间。
  double speechRate(String key) => doubleValue(
    key,
    defaultSpeechRate,
    min: minSpeechRate,
    max: maxSpeechRate,
  );

  Accent accent() =>
      _raw['defaultAccent'] == Accent.uk.wire ? Accent.uk : Accent.us;
}

List<VocabularyLevel> _examTargets(Object? value) {
  if (value is! List) return const <VocabularyLevel>[];
  final result = <VocabularyLevel>[];
  for (final item in value) {
    if (item is! String) continue;
    final level = VocabularyLevel.fromWire(item);
    if (level != VocabularyLevel.auto && !result.contains(level)) {
      result.add(level);
    }
  }
  return List<VocabularyLevel>.unmodifiable(result);
}
