/// 请求字段的选择、裁剪与合并。
///
/// 对应旧版 `modules/dictionary/selection.ts`。
///
/// **职责**：决定「这次初始化要哪些字段」「已有内容离目标还差什么」
/// 「新内容该覆盖还是只补空缺」，以及「哪些数据源值得调用」。
library;

import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
import 'package:lexiloop/data/dictionary/merge_content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/merge.dart';

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

/// 过滤并去重请求字段，剔除未知字段名。
List<String> normalizeRequestedFields(Iterable<String>? fields) {
  if (fields == null) return const <String>[];
  final result = <String>[];
  for (final field in fields) {
    if (!contentFields.contains(field)) continue;
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
    if (id == 'ai' && isAiProviderId(provider.id)) return provider;
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
