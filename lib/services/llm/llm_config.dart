/// LLM 配置的解析与归一化。
///
/// 对应旧版 `src/lib/types/settings.ts` 的 `LlmConfig` 与
/// `modules/settings/service.ts` 的 zod 校验。
///
/// **为什么留在 `settings.raw` 里**：`AppSettings` 只建模了学习计划、
/// 播放与数据源开关；LLM 配置结构深、字段多且只在设置页被读写。
/// 把它原样保留在 `raw` 中，既避免设置页每改一次学习设置就清空 AI 配置，
/// 也让本模块可以独立演进。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';

/// LLM 配置在 `settings.raw` 中的键名。
const String llmConfigSettingsKey = 'llmConfig';

/// LLM 接口协议。
enum LlmApiType {
  /// OpenAI 兼容（`POST {baseUrl}/chat/completions`）。
  openai('openai'),

  /// Anthropic（`POST {baseUrl}/messages`）。
  anthropic('anthropic');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值回退到 [LlmApiType.openai]。
  static LlmApiType fromWire(Object? wire) => wire == LlmApiType.anthropic.wire
      ? LlmApiType.anthropic
      : LlmApiType.openai;
}

/// 单个 LLM 提供方。
class LlmProviderConfig {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.name,
    required this.apiType,
    required this.baseUrl,
    required this.apiKey,
    this.models = const <String>[],
    this.defaultModel = '',
  });

  /// 稳定标识。
  final String id;

  /// 展示名。
  final String name;

  /// 接口协议。
  final LlmApiType apiType;

  /// 接口基址（已去掉尾部斜杠）。
  final String baseUrl;

  /// API Key。
  final String apiKey;

  /// 可选模型列表（「拉取模型列表」的结果）。
  final List<String> models;

  /// 默认模型。
  final String defaultModel;

  /// 配置是否可用于发起请求。
  bool get isUsable => baseUrl.isNotEmpty && apiKey.isNotEmpty;
}

/// 词条初始化 / 建议等用途共用的 AI 配置。
class LlmAiConfig {
  /// 以各字段构造。
  const new({
    required this.enabled,
    required this.providerId,
    required this.model,
    this.retryProviderId = '',
    this.retryModel = '',
    this.temperature = defaultLlmTemperature,
    this.maxOutputTokens = defaultLlmMaxOutputTokens,
    this.timeoutMs = defaultLlmTimeoutMs,
    this.thinkingEnabled = false,
    this.thinkingBudgetTokens = defaultThinkingBudgetTokens,
    this.reasoningEffort = '',
    this.retryCount = defaultAiRetryCount,
  });

  /// 是否启用。
  final bool enabled;

  /// 主提供方 ID。
  final String providerId;

  /// 主模型。
  final String model;

  /// 备用提供方 ID。
  final String retryProviderId;

  /// 备用模型。
  final String retryModel;

  /// 采样温度。
  final double temperature;

  /// 最大输出 token。
  final int maxOutputTokens;

  /// 请求超时（毫秒）。
  final int timeoutMs;

  /// 是否开启思考。
  final bool thinkingEnabled;

  /// 思考预算（token）。
  final int thinkingBudgetTokens;

  /// 推理强度（`minimal` / `low` / `medium` / `high`）。
  final String reasoningEffort;

  /// 重试遍数。
  final int retryCount;
}

/// LLM 配置。
class LlmConfig {
  /// 以各字段构造。
  const new({required this.providers, required this.ai});

  /// 全部提供方。
  final List<LlmProviderConfig> providers;

  /// 用途配置。
  final LlmAiConfig ai;

  /// 未配置任何 LLM 时的默认值。
  static const LlmConfig disabled = LlmConfig(
    providers: <LlmProviderConfig>[],
    ai: LlmAiConfig(enabled: false, providerId: '', model: ''),
  );

  /// 按 ID 查找提供方；找不到返回 `null`。
  LlmProviderConfig? providerById(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  /// 主提供方；未配置或不可用时返回 `null`。
  LlmProviderConfig? get primaryProvider => providerById(ai.providerId);

  /// 配置是否足以发起请求。
  bool get isUsable {
    final primary = primaryProvider;
    return ai.enabled &&
        primary != null &&
        primary.isUsable &&
        ai.model.trim().isNotEmpty;
  }
}

/// 从 `settings.raw['llmConfig']` 解析 LLM 配置。
///
/// 任何一层结构不符都退化为 [LlmConfig.disabled]，而不是抛错——
/// 设置页的脏数据不应该让初始化队列整体不可用。
LlmConfig llmConfigFromRaw(Object? raw) {
  if (raw is! Map) return LlmConfig.disabled;
  final providers = _providers(raw['providers']);
  final ai = _ai(raw['ai']);
  return LlmConfig(providers: providers, ai: ai);
}

List<LlmProviderConfig> _providers(Object? raw) {
  if (raw is! List) return const <LlmProviderConfig>[];
  final result = <LlmProviderConfig>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = _text(item['id']);
    if (id.isEmpty) continue;
    final models = <String>[];
    final rawModels = item['models'];
    if (rawModels is List) {
      for (final model in rawModels) {
        final value = _text(model);
        if (value.isNotEmpty) models.add(value);
      }
    }
    result.add(
      LlmProviderConfig(
        id: id,
        name: _text(item['name']),
        apiType: LlmApiType.fromWire(item['apiType']),
        baseUrl: normalizeBaseUrl(_text(item['baseUrl'])),
        apiKey: _text(item['apiKey']),
        models: models,
        defaultModel: _text(item['defaultModel']),
      ),
    );
  }
  return result;
}

LlmAiConfig _ai(Object? raw) {
  if (raw is! Map) {
    return const LlmAiConfig(enabled: false, providerId: '', model: '');
  }
  final limits = _aiLimits(raw);
  return LlmAiConfig(
    enabled: raw['enabled'] == true,
    providerId: _text(raw['providerId']),
    model: _text(raw['model']),
    retryProviderId: _text(raw['retryProviderId']),
    retryModel: _text(raw['retryModel']),
    thinkingEnabled: raw['thinkingEnabled'] == true,
    reasoningEffort: _text(raw['reasoningEffort']),
    temperature: limits.$1,
    maxOutputTokens: limits.$2,
    timeoutMs: limits.$3,
    thinkingBudgetTokens: limits.$4,
    retryCount: limits.$5,
  );
}

/// 数值字段的取值夹取。
///
/// 单独成函数是因为这里集中了 5 组「区间 + 默认值」，
/// 混在结构解析里会让 `_ai` 越过 40 行上限。
(double, int, int, int, int) _aiLimits(Map<dynamic, dynamic> raw) => (
  _clampDouble(
    raw['temperature'],
    defaultLlmTemperature,
    minLlmTemperature,
    maxLlmTemperature,
  ),
  _clampInt(
    raw['maxOutputTokens'],
    defaultLlmMaxOutputTokens,
    minLlmMaxOutputTokens,
    maxLlmMaxOutputTokens,
  ),
  _clampInt(
    raw['timeoutMs'],
    defaultLlmTimeoutMs,
    minLlmTimeoutMs,
    maxLlmTimeoutMs,
  ),
  _clampInt(
    raw['thinkingBudgetTokens'],
    defaultThinkingBudgetTokens,
    minThinkingBudgetTokens,
    maxThinkingBudgetTokens,
  ),
  _clampInt(raw['aiRetryCount'], defaultAiRetryCount, 1, maxAiRetryCount),
);

/// 去掉基址的尾部斜杠，避免拼出 `//chat/completions`。
String normalizeBaseUrl(String value) {
  var result = value.trim();
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _text(Object? value) => value is String ? value.trim() : '';

int _clampInt(Object? value, int fallback, int min, int max) =>
    value is num ? value.round().clamp(min, max) : fallback;

double _clampDouble(Object? value, double fallback, double min, double max) =>
    value is num ? value.toDouble().clamp(min, max) : fallback;
