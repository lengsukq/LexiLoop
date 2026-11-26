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

  /// 高考。
  gaokao('GAOKAO'),

  /// 大学英语四级。
  cet4('CET4'),

  /// 大学英语六级。
  cet6('CET6'),

  /// 考研。
  ky('KY'),

  /// 英语专业四级。
  tem4('TEM4'),

  /// 英语专业八级。
  tem8('TEM8'),

  /// 雅思。
  ielts('IELTS'),

  /// 托福。
  toefl('TOEFL'),

  /// GRE。
  gre('GRE');

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

/// 界面外观模式。
///
/// **为什么不直接用 Flutter 的 `ThemeMode`**：`lib/domain` 必须保持纯 Dart
/// （架构守卫禁止引入 Flutter），设置模型不能携带界面类型。界面层在
/// `ui/theme/lexi_appearance.dart` 里做一次映射。
enum AppThemeMode {
  /// 跟随系统。
  system('system'),

  /// 始终浅色。
  light('light'),

  /// 始终深色。
  dark('dark');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值返回 [AppThemeMode.system]。
  static AppThemeMode fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return AppThemeMode.system;
  }
}

/// 外观设置：模式、主色、次色。
///
/// 颜色存成 ARGB 整数而不是字符串，既避免解析歧义，也让「坏值」只有
/// 一个判断入口（[AppearanceSettings] 的解析器）。用户选的是色种，
/// 最终渲染色由主题引擎按明暗模式推导。
class AppearanceSettings {
  /// 以模式与两个色种构造。
  const new({
    required this.mode,
    required this.primaryColor,
    required this.secondaryColor,
  });

  /// 外观模式。
  final AppThemeMode mode;

  /// 主色色种（ARGB）。
  final int primaryColor;

  /// 次色色种（ARGB）。
  final int secondaryColor;

  /// 默认外观：跟随系统、薄荷绿主色、靛蓝次色。
  static const AppearanceSettings defaults = AppearanceSettings(
    mode: AppThemeMode.system,
    primaryColor: defaultThemePrimaryColor,
    secondaryColor: defaultThemeSecondaryColor,
  );

  /// 转回存储键值。
  Map<String, Object?> toStorage() => <String, Object?>{
    'themeMode': mode.wire,
    'themePrimaryColor': primaryColor,
    'themeSecondaryColor': secondaryColor,
  };
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

/// 可选发音引擎。
///
/// 用户可多选启用任意组合，并按拖动后的顺序决定优先级：
/// 排在前面的不可用或不适用（如长句跳过有道）时，自动顺延到下一个已启用引擎。
enum SpeechSource {
  /// 有道词典真人 MP3（直连 `dict.youdao.com/dictvoice` 或词典自带录音）。
  youdao('youdao', '有道词典发音', '在线真人 MP3，响应快；适合单词与常见短语'),

  /// Flutter 直连微软 Edge 神经网络语音。
  edge('edge', '微软 Edge 语音', '直连神经网络语音，单词与整句都自然流畅'),

  /// 设备本地系统 TTS。
  system('system', '设备系统朗读', '本地离线语音合成，断网也能兜底发音');

  new(this.wire, this.label, this.description);

  /// 存储值。
  final String wire;

  /// 设置界面中的名称。
  final String label;

  /// 设置界面中的一句说明。
  final String description;

  /// 解析存储值；兼容旧版 `dictionary` 写法，未知值返回 `null`。
  static SpeechSource? tryFromWire(String? value) => switch (value) {
    'youdao' || 'dictionary' => SpeechSource.youdao,
    'edge' => SpeechSource.edge,
    'system' => SpeechSource.system,
    _ => null,
  };
}

/// 发音优先级链中的单项配置。
class SpeechSourcePreference {
  /// 以引擎与启用状态构造。
  const new({required this.source, required this.enabled});

  /// 对应的发音引擎。
  final SpeechSource source;

  /// 是否启用该引擎。
  final bool enabled;

  /// 返回修改后的副本。
  SpeechSourcePreference copyWith({bool? enabled}) =>
      SpeechSourcePreference(source: source, enabled: enabled ?? this.enabled);

  /// 转为可写入设置表的 JSON Map。
  Map<String, Object?> toJson() => <String, Object?>{
    'source': source.wire,
    'enabled': enabled,
  };
}

/// 默认发音优先级链：有道真人 MP3 → 微软 Edge 语音 → 设备系统朗读。
const List<SpeechSourcePreference> defaultSpeechChain =
    <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: true),
      SpeechSourcePreference(source: SpeechSource.edge, enabled: true),
      SpeechSourcePreference(source: SpeechSource.system, enabled: true),
    ];

/// 学习选项中的释义密度；不修改判题使用的完整原文。
enum ChoiceDefinitionStyle {
  /// 仅展示前两个释义片段。
  compact('compact', '简洁'),

  /// 展示前四个释义片段。
  standard('standard', '标准'),

  /// 展示词典中全部释义。
  full('full', '完整');

  new(this.wire, this.label);

  /// 存储值。
  final String wire;

  /// 设置界面中的名称。
  final String label;

  /// 未知值降级为简洁展示。
  static ChoiceDefinitionStyle fromWire(String? value) {
    for (final style in values) {
      if (style.wire == value) return style;
    }
    return ChoiceDefinitionStyle.compact;
  }
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
    this.speechChain = defaultSpeechChain,
    this.choiceDefinitionStyle = ChoiceDefinitionStyle.compact,
    this.offlineAudioCacheEnabled = true,
    this.audioCacheMaxSizeMb = defaultAudioCacheMaxSizeMb,
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

  /// 按优先级排列的发音引擎列表（列表顺序即回退顺序，每项可独立开关）。
  final List<SpeechSourcePreference> speechChain;

  /// 学习选择题显示的释义密度。
  final ChoiceDefinitionStyle choiceDefinitionStyle;

  /// 是否将在线获取的发音持久化保存到本机磁盘。
  final bool offlineAudioCacheEnabled;

  /// 离线语音磁盘缓存上限（MB）；`0` 表示不限制。
  final int audioCacheMaxSizeMb;

  /// 默认值。
  static const PlaybackSettings defaults = PlaybackSettings(
    choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
    defaultAccent: Accent.us,
    wordSpeed: defaultSpeechRate,
    phraseSpeed: defaultSpeechRate,
    sentenceSpeed: defaultSpeechRate,
    autoPlayPronunciation: true,
  );

  /// 离线语音缓存上限换算为字节；`0` 表示不限制。
  int get audioCacheMaxBytes =>
      audioCacheMaxSizeMb <= 0 ? 0 : audioCacheMaxSizeMb * audioCacheBytesPerMb;

  /// 已启用的发音引擎，严格按用户排列的优先级返回。
  List<SpeechSource> get enabledSpeechSources => <SpeechSource>[
    for (final item in speechChain)
      if (item.enabled) item.source,
  ];

  /// 是否至少启用了一个发音引擎；全部关闭表示静音模式。
  bool get speechEnabled => speechChain.any((item) => item.enabled);

  /// 指定引擎当前是否启用。
  bool isSourceEnabled(SpeechSource source) =>
      speechChain.any((item) => item.source == source && item.enabled);

  /// 序列化发音优先级链供写入设置表。
  static List<Map<String, Object?>> serializeSpeechChain(
    List<SpeechSourcePreference> chain,
  ) => <Map<String, Object?>>[for (final item in chain) item.toJson()];

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
    'speechChain': serializeSpeechChain(speechChain),
    'choiceDefinitionStyle': choiceDefinitionStyle.wire,
    'offlineAudioCacheEnabled': offlineAudioCacheEnabled,
    'audioCacheMaxSizeMb': audioCacheMaxSizeMb,
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
    required this.appearance,
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

  /// 界面外观（模式、主色、次色）。
  final AppearanceSettings appearance;

  /// 默认设置（无任何用户配置时）。
  static const AppSettings defaults = AppSettings(
    raw: <String, Object?>{},
    studyPlan: StudyPlanSettings.defaults,
    playback: PlaybackSettings.defaults,
    providers: ProviderSettings.defaults,
    vocabularyLevel: VocabularyLevel.auto,
    examTargets: <VocabularyLevel>[],
    questionTypeConfig: QuestionTypeConfig.defaults,
    appearance: AppearanceSettings.defaults,
  );

  /// 合并为可写回存储的键值映射。
  ///
  /// 未建模的键从 [raw] 原样带出，避免保存时丢字段。
  Map<String, Object?> toStorage() => <String, Object?>{
    ...raw,
    ...studyPlan.toStorage(),
    ...playback.toStorage(),
    ...providers.toStorage(),
    ...appearance.toStorage(),
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
    appearance: _parseAppearance(reader),
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
    speechChain: _parseSpeechChain(reader),
    choiceDefinitionStyle: ChoiceDefinitionStyle.fromWire(
      reader.stringValue('choiceDefinitionStyle'),
    ),
    offlineAudioCacheEnabled: reader.boolValue(
      'offlineAudioCacheEnabled',
      fallback: fallback.offlineAudioCacheEnabled,
    ),
    audioCacheMaxSizeMb: reader.intValue(
      'audioCacheMaxSizeMb',
      fallback.audioCacheMaxSizeMb,
      min: 0,
      max: maxAudioCacheMaxSizeMb,
    ),
  );
}

List<SpeechSourcePreference> _parseSpeechChain(_SettingsReader reader) {
  final rawChain = reader._raw['speechChain'];
  if (rawChain is List<Object?>) {
    final parsed = _normalizeSpeechChain(rawChain);
    if (parsed.isNotEmpty) return parsed;
  }
  return _migrateLegacySpeechChain(reader);
}

List<SpeechSourcePreference> _normalizeSpeechChain(List<Object?> rawChain) {
  final seen = <SpeechSource>{};
  final result = <SpeechSourcePreference>[];
  for (final item in rawChain) {
    if (item is! Map<Object?, Object?>) continue;
    final wire = item['source'];
    final source = SpeechSource.tryFromWire(wire is String ? wire : null);
    if (source == null || !seen.add(source)) continue;
    final enabledRaw = item['enabled'];
    result.add(
      SpeechSourcePreference(
        source: source,
        enabled: enabledRaw is bool && enabledRaw,
      ),
    );
  }
  if (result.isEmpty) return result;
  for (final fallback in defaultSpeechChain) {
    if (seen.add(fallback.source)) {
      result.add(
        SpeechSourcePreference(source: fallback.source, enabled: false),
      );
    }
  }
  return List<SpeechSourcePreference>.unmodifiable(result);
}

/// 兼容升级前只存了 `speechSource` / `humanAudioEnabled` / `speechFallbackEnabled`
/// 的老设置，平滑映射为等价的优先级链。
List<SpeechSourcePreference> _migrateLegacySpeechChain(_SettingsReader reader) {
  final legacySource = reader.stringValue('speechSource');
  final humanAudio = reader.boolValue('humanAudioEnabled', fallback: true);
  final fallback = reader.boolValue('speechFallbackEnabled', fallback: true);
  return switch (legacySource) {
    'off' => _chain((SpeechSource.youdao, false), (SpeechSource.edge, false), (
      SpeechSource.system,
      false,
    )),
    'edge' || 'online' => _chain(
      (SpeechSource.edge, true),
      (SpeechSource.youdao, fallback),
      (SpeechSource.system, fallback),
    ),
    'dictionary' => _chain(
      (SpeechSource.youdao, true),
      (SpeechSource.edge, fallback),
      (SpeechSource.system, fallback),
    ),
    'system' => _chain(
      (SpeechSource.system, true),
      (SpeechSource.youdao, fallback && humanAudio),
      (SpeechSource.edge, fallback),
    ),
    _ when !humanAudio => _chain(
      (SpeechSource.system, true),
      (SpeechSource.youdao, false),
      (SpeechSource.edge, false),
    ),
    _ when !fallback => _chain(
      (SpeechSource.youdao, true),
      (SpeechSource.edge, false),
      (SpeechSource.system, false),
    ),
    _ => defaultSpeechChain,
  };
}

List<SpeechSourcePreference> _chain(
  (SpeechSource, bool) first,
  (SpeechSource, bool) second,
  (SpeechSource, bool) third,
) => List<SpeechSourcePreference>.unmodifiable(<SpeechSourcePreference>[
  SpeechSourcePreference(source: first.$1, enabled: first.$2),
  SpeechSourcePreference(source: second.$1, enabled: second.$2),
  SpeechSourcePreference(source: third.$1, enabled: third.$2),
]);

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

AppearanceSettings _parseAppearance(_SettingsReader reader) {
  const fallback = AppearanceSettings.defaults;
  return AppearanceSettings(
    mode: AppThemeMode.fromWire(reader.stringValue('themeMode')),
    primaryColor: reader.colorInt('themePrimaryColor', fallback.primaryColor),
    secondaryColor: reader.colorInt(
      'themeSecondaryColor',
      fallback.secondaryColor,
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

  /// 读取字符串；类型不符或为空时返回 `null`。
  String? stringValue(String key) {
    final value = _raw[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 读取 ARGB 色种。
  ///
  /// 只接受整数：字符串色值（如 `"#35C989"`）在不同来源里含义不一，
  /// 与其猜格式，不如当成坏值回默认。透明色一律补成不透明——主题色
  /// 带 alpha 会让按钮底与卡片底互相透出，不是用户想要的。
  int colorInt(String key, int fallback) {
    final value = _raw[key];
    if (value is! num) return fallback;
    final rounded = value.round();
    if (rounded < 0 || rounded > 0xFFFFFFFF) return fallback;
    return 0xFF000000 | (rounded & 0x00FFFFFF);
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
