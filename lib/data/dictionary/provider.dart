/// 词典 / 翻译 provider 的接口与共享类型。
///
/// 对应旧版 `modules/dictionary/provider.ts` 与 `pipeline.ts` 的
/// `PROVIDER_CAPABILITIES`。
///
/// **与旧版的差异**：旧版 `ProviderResult` 用 `errorCode` 字符串表达失败，
/// 调用方要靠 `errorCode === "NOT_FOUND"` 之类的比较分支；这里改成
/// 「成功返回 [ProviderResult]，无内容返回 `null`，失败抛
/// `ExternalServiceError`」，失败原因由类型化的错误码承载。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 一次 provider 调用的输入。
class ProviderRequest {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.contentType,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.wantedFields,
  });

  /// 待查询文本。
  final String term;

  /// 词条内容类型。
  final LexicalContentType contentType;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 本次要求的字段（逻辑字段名）；空集表示「不限定」。
  final Set<String> wantedFields;

  /// 是否要求某个字段。
  bool wants(String field) =>
      wantedFields.isEmpty || wantedFields.contains(field);
}

/// 一次 provider 调用的结果。
class ProviderResult {
  /// 以各字段构造。
  const new({
    required this.fields,
    required this.providerId,
    this.qualityScore = 0,
    this.metadata,
  });

  /// 逻辑字段名 → JSON 可序列化的值（**不预先编码成字符串**）。
  final Map<String, Object?> fields;

  /// 产出该结果的 provider 标识（AI 类带 `ai:` 前缀）。
  final String providerId;

  /// 质量分（0–100），供 `PRIORITY_FALLBACK` 决定是否继续下一个来源。
  final int qualityScore;

  /// 审计元数据（写进 `provider_attempts.metadata_json`）。
  final Map<String, Object?>? metadata;
}

/// 数据源单次调用的审计记录。
///
/// 对应 `provider_attempts` 表的一行。
class ProviderAttemptRecord {
  /// 以各字段构造。
  const new({
    required this.providerId,
    required this.status,
    required this.durationMs,
    required this.fieldsReturned,
    this.errorCode,
    this.errorMessage,
    this.metadata,
  });

  /// 数据源标识。
  final String providerId;

  /// 调用结果状态。
  final ProviderAttemptStatus status;

  /// 耗时（毫秒）。
  final int durationMs;

  /// 实际返回的字段。
  final List<String> fieldsReturned;

  /// 失败时的错误码（`AppErrorCode.code`）。
  final String? errorCode;

  /// 失败时的错误说明。
  final String? errorMessage;

  /// 审计元数据。
  final Map<String, Object?>? metadata;
}

/// 词典 / 翻译 provider。
abstract interface class DictionaryProvider {
  /// 稳定标识，与旧版逐字一致（`youdao`、`iciba`、`dictionaryapi.dev`、
  /// `mymemory`、`merriam-webster`，AI 类为 `ai:<provider>:<model>`）。
  String get id;

  /// 该 provider 能产出哪些字段。
  Set<String> get providedFields;

  /// 该 provider 是否已被用户启用且配置完整。
  bool isEnabled(AppSettings settings);

  /// 该 provider 是否支持这次请求（语言对与内容类型）。
  ///
  /// 旧版把这条判断塞在 `supports(input)` 里，但没有抽象进接口，
  /// 导致 selection 阶段只能按 id 硬编码分支。这里显式建模。
  bool supports(ProviderRequest request);

  /// 拉取内容。
  ///
  /// 成功但**没有可用内容**时返回 `null`（对应 `EMPTY` 尝试）；
  /// 调用失败时抛 [ExternalServiceError]，瞬时失败把 `isTransient` 置真。
  Future<ProviderResult?> fetch(ProviderRequest request);
}

/// 各 provider 的能力表。
///
/// 与旧版 `PROVIDER_CAPABILITIES` 逐条对应；`ai` 是 AI 类 provider 的
/// 聚合键（`ai:<provider>:<model>` 都归到 `ai`）。
const Map<String, Set<String>> providerCapabilities = <String, Set<String>>{
  'merriam-webster': <String>{
    'definitions',
    'pronunciations.phonetic',
    'pronunciations.audio',
    'examples',
    'synonyms',
    'antonyms',
  },
  'dictionaryapi.dev': <String>{
    'definitions',
    'pronunciations.phonetic',
    'pronunciations.audio',
    'examples',
    'synonyms',
    'antonyms',
  },
  'youdao': <String>{
    'definitions',
    'pronunciations.phonetic',
    'pronunciations.audio',
    'examples',
    'phrases',
    'forms',
    'synonyms',
    'antonyms',
    'wordFamily',
    'roots',
    'affixes',
    'summary',
    'tags',
  },
  'iciba': <String>{
    'definitions',
    'pronunciations.phonetic',
    'pronunciations.audio',
    'examples',
    'phrases',
    'forms',
    'synonyms',
    'antonyms',
    'wordFamily',
    'roots',
    'affixes',
    'summary',
    'tags',
  },
  'ai': <String>{
    'definitions',
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
    'summary',
    'learning',
    'sentenceAnalysis',
  },
  'mymemory': <String>{'definitions'},
};

/// 句子类词条上，有道与爱词霸实际只会产出这些字段。
///
/// 旧版在 `supportsRequestedFields` 里内联了这个集合；句子页面上勾选
/// `synonyms` 之类无效字段时直接跳过该来源，避免白跑一次请求。
const Set<String> sentenceSupportedProviderFields = <String>{
  'definitions',
  'summary',
  'examples',
  'phrases',
};

/// 把 provider 标识折叠为能力表键（`ai:...` → `ai`）。
String providerCapabilityKey(String providerId) =>
    providerId.startsWith(aiProviderIdPrefix) ? 'ai' : providerId;

/// AI 类 provider 标识的前缀。
const String aiProviderIdPrefix = 'ai:';

/// 该标识是否是 AI 类 provider。
bool isAiProviderId(String providerId) =>
    providerId.startsWith(aiProviderIdPrefix);

/// 目标语言释义的字段名常量。
const String definitionsField = 'definitions';

/// 音标字段名常量。
const String phoneticField = 'pronunciations.phonetic';

/// 音频字段名常量。
const String audioField = 'pronunciations.audio';

/// 摘要字段名常量。
const String summaryField = 'summary';
