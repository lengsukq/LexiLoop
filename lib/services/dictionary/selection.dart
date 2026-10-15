/// 请求字段的选择、裁剪与合并。
///
/// 对应旧版 `modules/dictionary/selection.ts`。
///
/// **职责**：决定「这次初始化要哪些字段」「已有内容离目标还差什么」
/// 「新内容该覆盖还是只补空缺」，以及「哪些数据源值得调用」。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/merge_content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/merriam_webster.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

/// 默认的数据源调用顺序。
///
/// AI **不在**默认顺序里：默认初始化必须由词典内容支撑，
/// AI 作为显式补充任务单独入队（旧版同样的取舍）。
const List<String> defaultTranslationProviderOrder = <String>[
  'youdao',
  'iciba',
  'merriam-webster',
  'dictionaryapi.dev',
  'mymemory',
];

/// 初始化可请求的全部字段。
///
/// **来源**：[providerCapabilities] 五个能力键的并集（16 项），与旧版
/// `INITIALIZATION_FIELDS` 逐字对应。
///
/// **为什么不是 [contentFields]**：`pronunciations.phonetic` 与
/// `pronunciations.audio` 是音标与音频两个可独立请求的子字段，
/// 而 `pronunciations` 只是它们在 `word_contents` 里的合列。
/// 管线的四处判定（[projectDictionaryContent]、[mergeRequestedFields]、
/// [hasInitializationField]、[supportsRequestedFields]）都按这两个名字
/// 分支，规范化时把它们挡在门外会让「仅补音标」静默退化成「补全全部字段」。
const List<String> initializationFields = <String>[
  definitionsField,
  phoneticField,
  audioField,
  'examples',
  'phrases',
  'forms',
  'synonyms',
  'antonyms',
  'wordFamily',
  'confusedWords',
  'roots',
  'affixes',
  'tags',
  summaryField,
  'learning',
  'sentenceAnalysis',
];

/// 过滤并去重请求字段，剔除未知字段名。
List<String> normalizeRequestedFields(Iterable<String>? fields) {
  if (fields == null) return const <String>[];
  final result = <String>[];
  for (final field in fields) {
    if (!initializationFields.contains(field)) continue;
    if (result.contains(field)) continue;
    result.add(field);
  }
  return result;
}

/// 内容是否已经具备某字段。
bool hasInitializationField(DictionaryContent content, String field) {
  switch (field) {
    case phoneticField:
      return _hasPronunciation(content, audio: false);
    case audioField:
      return _hasPronunciation(content, audio: true);
    case summaryField:
      final summary = content.record(summaryField);
      return _nonEmpty(summary['shortDefinition']) ||
          _nonEmpty(summary['translation']) ||
          summary['cefrLevel'] != null ||
          summary['frequency'] != null;
    case 'learning':
      final learning = content.record('learning');
      return _nonEmpty(learning['pronunciationTip']) ||
          _nonEmpty(learning['mnemonic']) ||
          content.strings('commonMistakes').isNotEmpty;
    case 'sentenceAnalysis':
      final analysis = content.record('sentenceAnalysis');
      return _nonEmpty(analysis['grammarPattern']) &&
          _nonEmpty(analysis['grammarExplanation']) &&
          content.strings('grammarNotes').isNotEmpty &&
          content.records('similarExamples').length >=
              sentenceAnalysisMinSimilarExamples;
    default:
      return content.records(field).isNotEmpty ||
          content.strings(field).isNotEmpty;
  }
}

/// 请求字段的完成状态（不考虑语言对）。
InitializationStatus requestedFieldStatus(
  DictionaryContent content,
  List<String> fields,
) {
  if (fields.isEmpty) {
    if (content.records(definitionsField).isEmpty) {
      return InitializationStatus.failed;
    }
    return content.records('examples').isEmpty
        ? InitializationStatus.partial
        : InitializationStatus.ready;
  }
  var present = 0;
  for (final field in fields) {
    if (hasInitializationField(content, field)) present += 1;
  }
  if (present == fields.length) return InitializationStatus.ready;
  return present > 0
      ? InitializationStatus.partial
      : InitializationStatus.failed;
}

/// 请求字段的完成状态，额外要求目标语言释义存在。
///
/// 只统计「有释义但都不是目标语言」的情况：这时内容可用但判题会出问题，
/// 必须降级为 [InitializationStatus.partial] 而不能算完成。
InitializationStatus requestedFieldStatusForLanguages(
  DictionaryContent content,
  List<String> fields,
  String sourceLanguage,
  String targetLanguage,
) {
  final status = requestedFieldStatus(content, fields);
  final definitionsRequired =
      fields.isEmpty || fields.contains(definitionsField);
  if (!definitionsRequired || sourceLanguage == targetLanguage) return status;
  final definitions = content.records(definitionsField);
  final hasTarget = definitions.any(
    (item) => item['language'] == targetLanguage && _nonEmpty(item['text']),
  );
  if (hasTarget) return status;
  return definitions.any((item) => _nonEmpty(item['text']))
      ? InitializationStatus.partial
      : status;
}

/// 实际返回的字段列表。
List<String> fieldsReturned(
  DictionaryContent content,
  List<String> requestedFields,
) {
  final candidates = requestedFields.isEmpty ? contentFields : requestedFields;
  return <String>[
    for (final field in candidates)
      if (hasInitializationField(content, field)) field,
  ];
}

/// 按请求字段裁剪内容。
DictionaryContent projectDictionaryContent(
  DictionaryContent content,
  List<String> requestedFields,
) {
  if (requestedFields.isEmpty) return content;
  var result = emptyDictionaryContent();
  for (final field in requestedFields) {
    if (field == phoneticField || field == audioField) {
      result = result.withField(
        'pronunciations',
        content.fields['pronunciations'],
      );
    } else if (field == summaryField ||
        field == 'learning' ||
        field == 'sentenceAnalysis') {
      result = result.withField(field, content.fields[field]);
    } else if (contentFields.contains(field)) {
      result = result.withField(field, content.fields[field]);
    }
  }
  return result;
}

/// 合并已有内容与新增内容。
///
/// [requestedFields] 为空时退化为整份合并；非空时只处理被点名的字段，
/// 并遵守 [mode]：`FILL_MISSING_FIELDS` 只补空缺，
/// `FORCE_OVERWRITE` 覆盖但保留用户产出（手工释义 / 手工例句）。
DictionaryContent mergeRequestedFields({
  required DictionaryContent existing,
  required DictionaryContent incoming,
  required List<String> requestedFields,
  required InitializationMode mode,
}) {
  final force = mode == InitializationMode.forceOverwrite;
  if (requestedFields.isEmpty) {
    if (!force) {
      return mergeDictionaryContent(<DictionaryContent>[existing, incoming]);
    }
    return mergeDictionaryContent(<DictionaryContent>[
      _userProduced(existing),
      incoming,
    ]);
  }
  var result = existing;
  for (final field in requestedFields) {
    result = _mergeField(
      result: result,
      incoming: incoming,
      field: field,
      force: force,
    );
  }
  return result;
}

/// 只保留用户产出的释义与例句。
DictionaryContent _userProduced(DictionaryContent content) =>
    DictionaryContent(<String, Object?>{
      'definitions': <Object?>[
        for (final item in content.records(definitionsField))
          if (isUserProtectedItem(definitionsField, item)) item,
      ],
      'examples': <Object?>[
        for (final item in content.records('examples'))
          if (isUserProtectedItem('examples', item)) item,
      ],
    });

DictionaryContent _mergeField({
  required DictionaryContent result,
  required DictionaryContent incoming,
  required String field,
  required bool force,
}) {
  if (field == phoneticField) {
    return result.withField(
      'pronunciations',
      mergePronunciationField(
        existing: result.records('pronunciations'),
        incoming: incoming.records('pronunciations'),
        audio: false,
        force: force,
      ),
    );
  }
  if (field == audioField) {
    return result.withField(
      'pronunciations',
      mergePronunciationField(
        existing: result.records('pronunciations'),
        incoming: incoming.records('pronunciations'),
        audio: true,
        force: force,
      ),
    );
  }
  if (field == summaryField ||
      field == 'learning' ||
      field == 'sentenceAnalysis') {
    if (!hasInitializationField(incoming, field)) return result;
    final merged = force
        ? incoming.fields[field]
        : mergeObjectField(field, result.fields[field], incoming.fields[field]);
    return result.withField(field, merged);
  }
  return _mergeArrayField(
    result: result,
    incoming: incoming,
    field: field,
    force: force,
  );
}

DictionaryContent _mergeArrayField({
  required DictionaryContent result,
  required DictionaryContent incoming,
  required String field,
  required bool force,
}) {
  final incomingItems = <Object?>[
    if (field == 'tags')
      ...incoming.strings(field)
    else
      ...incoming.records(field),
  ];
  if (incomingItems.isEmpty) return result;
  final existingItems = field == 'tags'
      ? result.strings(field).cast<Object?>()
      : result.records(field).cast<Object?>();
  if (force && (field == definitionsField || field == 'examples')) {
    final kept = <Object?>[
      for (final item in existingItems)
        if (item is Map &&
            isUserProtectedItem(field, item.cast<String, Object?>()))
          item,
    ];
    final merged = mergeContentFields(<Map<String, Object?>?>[
      <String, Object?>{field: kept},
      <String, Object?>{field: incomingItems},
    ]);
    return result.withField(field, merged[field]);
  }
  if (!force && existingItems.isNotEmpty) return result;
  return result.withField(field, incomingItems);
}

/// 选择本次要调用的数据源。
///
/// 顺序来源优先级：显式 `selectedProviders` > 设置里的
/// `translationProviderOrder` > [defaultTranslationProviderOrder]。
/// 之后按「已启用 / 支持该请求 / 能力与请求字段有交集」三层过滤。
List<DictionaryProvider> selectProviders({
  required AppSettings settings,
  required ProviderRequest request,
  required List<DictionaryProvider> candidates,
  List<String> selectedProviders = const <String>[],
}) {
  final order = _providerOrder(settings, selectedProviders);
  final result = <DictionaryProvider>[];
  final used = <String>{};
  for (final id in order) {
    final provider = _resolveProvider(id, candidates);
    if (provider == null || !used.add(provider.id)) continue;
    if (!provider.isEnabled(settings)) continue;
    if (!provider.supports(request)) continue;
    if (!supportsRequestedFields(provider, request)) continue;
    result.add(provider);
  }
  return result;
}

/// 该数据源的能力是否与请求字段有交集。
bool supportsRequestedFields(
  DictionaryProvider provider,
  ProviderRequest request,
) {
  final fields = request.wantedFields;
  if (fields.isEmpty) return true;
  final key = providerCapabilityKey(provider.id);
  final capabilities = providerCapabilities[key] ?? const <String>{};
  if (!fields.any(capabilities.contains)) return false;
  if (request.contentType != LexicalContentType.sentence) return true;
  if (key != 'youdao' && key != 'iciba') return true;
  // 句子页面上有道/爱词霸只产出这四类字段，勾了别的就是白跑一次请求。
  return fields.any(sentenceSupportedProviderFields.contains);
}

List<String> _providerOrder(
  AppSettings settings,
  List<String> selectedProviders,
) {
  if (selectedProviders.isNotEmpty) {
    final result = <String>[];
    for (final id in selectedProviders) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }
  final saved = settings.raw['translationProviderOrder'];
  if (saved is List) {
    final result = <String>[];
    for (final item in saved) {
      if (item is String && item.isNotEmpty && !result.contains(item)) {
        result.add(item);
      }
    }
    if (result.isNotEmpty) return result;
  }
  return defaultTranslationProviderOrder;
}

DictionaryProvider? _resolveProvider(
  String id,
  List<DictionaryProvider> candidates,
) {
  for (final provider in candidates) {
    if (provider.id == id) return provider;
    if (id == aiProviderSelectorId && isAiProviderId(provider.id)) {
      return provider;
    }
  }
  return null;
}

bool _hasPronunciation(DictionaryContent content, {required bool audio}) {
  for (final item in content.records('pronunciations')) {
    if (audio ? _nonEmpty(item['audioUrl']) : _nonEmpty(item['phonetic'])) {
      return true;
    }
  }
  return false;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

/// 一个数据源当前能否被调用，以及不能调用时的原因。
///
/// **为什么不直接暴露 [selectProviders] 的过滤结果**：
/// `selectProviders` 收的是一整批来源并丢掉不合格的，界面要展示的恰恰是
/// 被丢掉的那部分（以及为什么），否则用户只会看到一个少了几项的来源列表，
/// 无从判断是「去设置里开」还是「换几个字段」。
class ProviderAvailability {
  /// 以可用性与不可用原因构造。
  const new({required this.available, this.reason});

  /// 是否可被本次调用选中。
  final bool available;

  /// 不可用原因；可用时为 `null`。
  final String? reason;
}

/// 数据源在「这次请求」下的可用性。
///
/// 判据与 [selectProviders] 的三层过滤**逐条同源**：未启用
/// （[DictionaryProvider.isEnabled]）、不支持该请求（`supports`）、
/// 能力与请求字段无交集（[supportsRequestedFields]）。这里只补一件事——
/// 把「不可用」翻译成用户能照着做的中文原因。
ProviderAvailability providerAvailability({
  required DictionaryProvider provider,
  required AppSettings settings,
  required ProviderRequest request,
}) {
  if (!provider.isEnabled(settings)) {
    final reason = _configurationReason(settings, provider.id);
    return ProviderAvailability(
      available: false,
      reason: reason ?? providerDisabledReason,
    );
  }
  if (!provider.supports(request)) {
    return const ProviderAvailability(
      available: false,
      reason: providerRequestUnsupportedReason,
    );
  }
  if (!supportsRequestedFields(provider, request)) {
    return const ProviderAvailability(
      available: false,
      reason: providerFieldMismatchReason,
    );
  }
  return const ProviderAvailability(available: true);
}

/// 数据源已启用但缺少必要凭据时的原因；配置完整时返回 `null`。
///
/// 这里读的是与各 provider 的 `isEnabled` 同一批设置键，
/// 因此「界面上说可用、运行时被跳过」不会发生——`isEnabled` 仍是
/// 最终判据，本函数只负责让原因可读。
String? _configurationReason(AppSettings settings, String providerId) {
  if (providerId == merriamWebsterProviderId) {
    final configured =
        _rawText(settings, merriamWebsterDictionaryKeyName) +
        _rawText(settings, merriamWebsterThesaurusKeyName);
    return configured.isEmpty ? providerKeyMissingReason : null;
  }
  if (!isAiProviderId(providerId)) return null;
  final config = llmConfigFromSettings(settings.raw);
  if (config.isUsable) return null;
  if (!config.ai.enabled) return aiDisabledReason;
  if (config.primaryProvider == null) return aiProviderMissingReason;
  return aiIncompleteReason;
}

String _rawText(AppSettings settings, String key) {
  final value = settings.raw[key];
  return value is String ? value.trim() : '';
}

/// 数据源在设置里被关掉时的原因。
const String providerDisabledReason = '请先在设置中启用该数据源';

/// 需要 API Key 的数据源缺少凭据时的原因。
const String providerKeyMissingReason = '尚未配置 API Key';

/// 数据源不支持本次语言或词条类型时的原因。
const String providerRequestUnsupportedReason = '不支持当前语言或词条类型';

/// 数据源能力与所选字段没有交集时的原因。
const String providerFieldMismatchReason = '与所选字段没有交集';

/// AI 词条初始化用途未启用时的原因。
const String aiDisabledReason = 'AI 词条初始化未启用';

/// AI 主提供方不存在时的原因。
const String aiProviderMissingReason = 'AI Provider 不存在';

/// AI 配置缺项时的原因。
const String aiIncompleteReason = 'AI 配置不完整（缺少 API Key、Base URL 或模型名）';
