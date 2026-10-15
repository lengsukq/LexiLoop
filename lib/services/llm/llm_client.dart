/// LLM 客户端。
///
/// 对应旧版 `modules/llm/client.ts`（581 行）与 `llm/service.ts`。
///
/// **三层降级**（旧版行为，逐条复刻）：
/// 1. 同一 provider 内换备用模型（`ai.retryModel`）；
/// 2. 换备用 provider（`ai.retryProviderId`）+ 备用模型；
/// 3. 全部失败后抛错。
/// 只有 `isTransient` 的错误才降级——鉴权失败与响应格式错误切换目标
/// 只会浪费配额，且会把「Key 配错了」这个明确问题伪装成「服务不稳定」。
///
/// **`ai.retryCount` 的语义**：整份候选链重放的遍数。默认 1 遍，
/// 即主模型 → 备用模型 → 备用 provider 各试一次。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/llm/llm_json.dart';

/// 一次 LLM 请求的参数。
class LlmCallOptions {
  /// 以各字段构造。
  const new({
    required this.system,
    required this.user,
    this.schema,
    this.maxOutputTokens = defaultLlmMaxOutputTokens,
    this.temperature = defaultLlmTemperature,
    this.thinkingEnabled = false,
    this.thinkingBudgetTokens = defaultThinkingBudgetTokens,
    this.reasoningEffort = '',
  });

  /// 系统提示词。
  final String system;

  /// 用户提示词。
  final String user;

  /// 期望的 JSON Schema（为空表示普通文本输出）。
  final Map<String, Object?>? schema;

  /// 最大输出 token。
  final int maxOutputTokens;

  /// 采样温度。
  final double temperature;

  /// 是否开启思考。
  final bool thinkingEnabled;

  /// 思考预算（token）。
  final int thinkingBudgetTokens;

  /// 推理强度。
  final String reasoningEffort;
}

/// 归一化后的请求目标。
class LlmTarget {
  /// 以各字段构造。
  const new({
    required this.providerId,
    required this.apiType,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.timeoutMs,
  });

  /// 提供方 ID。
  final String providerId;

  /// 接口协议。
  final LlmApiType apiType;

  /// 接口基址。
  final String baseUrl;

  /// API Key。
  final String apiKey;

  /// 模型名。
  final String model;

  /// 请求超时（毫秒）。
  final int timeoutMs;

  /// 去重键（同一物理端点同一模型只试一次）。
  String get identity => '${apiType.wire}|$baseUrl|$apiKey|$model';
}

/// LLM 请求结果。
class LlmCompletion {
  /// 以各字段构造。
  const new({
    required this.text,
    required this.providerId,
    required this.model,
    this.inputTokens,
    this.outputTokens,
    this.finishReason,
  });

  /// 模型输出的正文。
  final String text;

  /// 提供方 ID。
  final String providerId;

  /// 模型名。
  final String model;

  /// 输入 token 数。
  final int? inputTokens;

  /// 输出 token 数。
  final int? outputTokens;

  /// 结束原因（`stop` / `length` / `max_tokens` / …）。
  final String? finishReason;
}

/// OpenAI 兼容端点的结构化输出档位。
class _OpenAiFormat {
  const _OpenAiFormat({
    required this.responseFormat,
    required this.appendSchema,
  });

  final Object? responseFormat;
  final bool appendSchema;
}

/// LLM 客户端。
class LlmClient {
  /// 以 HTTP 客户端与配置构造。
  const new(this._fetcher, this._config);

  final HttpFetcher _fetcher;
  final LlmConfig _config;

  /// 解析出要依次尝试的请求目标（主 → 备用模型 → 备用 provider）。
  List<LlmTarget> resolveTargets() {
    final ai = _config.ai;
    final primary = _config.providerById(ai.providerId);
    if (!ai.enabled || primary == null || !primary.isUsable) {
      return const <LlmTarget>[];
    }
    if (ai.model.trim().isEmpty) return const <LlmTarget>[];
    final targets = <LlmTarget>[_targetFor(primary, ai.model, ai.timeoutMs)];
    final retryModel = ai.retryModel.trim();
    if (retryModel.isNotEmpty && retryModel != ai.model) {
      targets.add(_targetFor(primary, retryModel, ai.timeoutMs));
    }
    final retryProviderId = ai.retryProviderId.trim().isEmpty
        ? primary.id
        : ai.retryProviderId.trim();
    final retryProvider = _config.providerById(retryProviderId);
    if (retryProvider != null &&
        retryProvider.isUsable &&
        retryProvider.id != primary.id) {
      targets.add(
        _targetFor(
          retryProvider,
          _retryProviderModel(retryProvider),
          ai.timeoutMs,
        ),
      );
    }
    return _dedupe(targets);
  }

  /// 发起一次请求，按三层降级依次尝试。
  Future<LlmCompletion> complete(LlmCallOptions options) async {
    final targets = resolveTargets();
    if (targets.isEmpty) {
      throw const ExternalServiceError(
        AppErrorCode.aiConfigIncomplete,
        details: 'LLM 未启用，或提供方 / Base URL / API Key / 模型不完整',
      );
    }
    ExternalServiceError? lastError;
    final passes = _config.ai.retryCount;
    for (var pass = 0; pass < passes; pass += 1) {
      for (final target in targets) {
        try {
          return await _request(target, options);
        } on ExternalServiceError catch (error) {
          if (!error.isTransient) rethrow;
          lastError = error;
        }
      }
    }
    throw lastError ??
        const ExternalServiceError(
          AppErrorCode.aiRequestFailed,
          isTransient: true,
          details: '全部 LLM 目标均失败',
        );
  }

  /// 发起一次请求并解析为 JSON 对象。
  ///
  /// 解析失败抛 [AppErrorCode.aiResponseInvalid]（完全没有 JSON），
  /// 结构不符抛 [AppErrorCode.aiSchemaInvalid]（有 JSON 但不是对象）。
  Future<Map<String, Object?>> completeJson({
    required String system,
    required String user,
    required Map<String, Object?> schema,
  }) async {
    final completion = await complete(
      LlmCallOptions(system: system, user: user, schema: schema),
    );
    final decoded = extractJsonValue(completion.text);
    if (decoded == null) {
      throw ExternalServiceError(
        AppErrorCode.aiResponseInvalid,
        details: _snippet(completion.text),
      );
    }
    if (decoded is! Map) {
      throw const ExternalServiceError(
        AppErrorCode.aiSchemaInvalid,
        details: '模型输出不是 JSON 对象',
      );
    }
    return decoded.cast<String, Object?>();
  }

  /// 拉取提供方的模型列表（`GET {baseUrl}/models`）。
  Future<List<String>> listModels(LlmProviderConfig provider) async {
    if (!provider.isUsable) {
      throw const ExternalServiceError(
        AppErrorCode.aiConfigIncomplete,
        details: 'Provider 缺少 Base URL 或 API Key',
      );
    }
    final target = LlmTarget(
      providerId: provider.id,
      apiType: provider.apiType,
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: provider.defaultModel,
      timeoutMs: modelListTimeoutMs,
    );
    final response = await _send(
      () => _fetcher.get(
        '${target.baseUrl}/models',
        timeout: const Duration(milliseconds: modelListTimeoutMs),
        headers: _headers(target),
      ),
    );
    if (!response.isSuccess) throw _httpError(response);
    final decoded = _decodeBody(response.body);
    if (decoded is! Map) return const <String>[];
    final data = decoded['data'];
    if (data is! List) return const <String>[];
    final result = <String>[];
    for (final item in data) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is String && id.trim().isNotEmpty) result.add(id.trim());
    }
    return result;
  }

  LlmTarget _targetFor(
    LlmProviderConfig provider,
    String model,
    int timeoutMs,
  ) => LlmTarget(
    providerId: provider.id,
    apiType: provider.apiType,
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    model: model,
    timeoutMs: timeoutMs,
  );

  String _retryProviderModel(LlmProviderConfig retryProvider) {
    final retryModel = _config.ai.retryModel.trim();
    if (retryModel.isNotEmpty) return retryModel;
    if (retryProvider.defaultModel.isNotEmpty) {
      return retryProvider.defaultModel;
    }
    return _config.ai.model;
  }

  List<LlmTarget> _dedupe(List<LlmTarget> targets) {
    final seen = <String>{};
    final result = <LlmTarget>[];
    for (final target in targets) {
      if (seen.add(target.identity)) result.add(target);
    }
    return result;
  }

  Future<LlmCompletion> _request(LlmTarget target, LlmCallOptions options) =>
      target.apiType == LlmApiType.anthropic
      ? _requestAnthropic(target, options)
      : _requestOpenAi(target, options);

  Future<LlmCompletion> _requestAnthropic(
    LlmTarget target,
    LlmCallOptions options,
  ) async {
    var response = await _post(
      target,
      '/messages',
      _anthropicBody(target, options, options.thinkingEnabled),
    );
    if (!response.isSuccess &&
        options.thinkingEnabled &&
        _shouldRetryWithoutThinking(response)) {
      response = await _post(
        target,
        '/messages',
        _anthropicBody(target, options, false),
      );
    }
    if (!response.isSuccess) throw _httpError(response);
    final body = _decodeBody(response.body);
    _assertModelBody(body, response.body, LlmApiType.anthropic);
    final completion = _parseAnthropic(body, target);
    if (completion.text.isEmpty) throw _emptyResponse();
    return completion;
  }

  Future<LlmCompletion> _requestOpenAi(
    LlmTarget target,
    LlmCallOptions options,
  ) async {
    ExternalServiceError? lastError;
    for (final format in _openAiFormats(options.schema)) {
      final response = await _post(
        target,
        '/chat/completions',
        _openAiBody(target, options, format),
      );
      if (!response.isSuccess) {
        final error = _httpError(response);
        if (response.statusCode == httpBadRequestStatus &&
            format.responseFormat != null) {
          lastError = error;
          continue;
        }
        throw error;
      }
      final body = _decodeBody(response.body);
      _assertModelBody(body, response.body, LlmApiType.openai);
      final refusal = _openAiRefusal(body);
      if (refusal != null) throw _refusalError(refusal);
      final completion = _parseOpenAi(body, target);
      if (completion.finishReason == _lengthFinishReason) {
        throw _truncationError();
      }
      if (completion.text.isEmpty) {
        lastError = _emptyResponse();
        continue;
      }
      return completion;
    }
    throw lastError ?? _emptyResponse();
  }

  Map<String, Object?> _anthropicBody(
    LlmTarget target,
    LlmCallOptions options,
    bool withThinking,
  ) {
    final maxTokens = withThinking
        ? math.max(
            options.maxOutputTokens,
            options.thinkingBudgetTokens +
                options.maxOutputTokens +
                anthropicThinkingOutputHeadroomTokens,
          )
        : options.maxOutputTokens;
    return <String, Object?>{
      'model': target.model,
      'max_tokens': maxTokens,
      'system': options.system,
      'messages': <Object?>[
        <String, Object?>{'role': 'user', 'content': _promptFor(options)},
      ],
      if (withThinking)
        'thinking': <String, Object?>{
          'type': 'enabled',
          'budget_tokens': options.thinkingBudgetTokens,
        },
      'temperature': withThinking
          ? llmThinkingTemperature
          : options.temperature,
    };
  }

  Map<String, Object?> _openAiBody(
    LlmTarget target,
    LlmCallOptions options,
    _OpenAiFormat format,
  ) {
    final payload = <String, Object?>{
      'model': target.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': options.system},
        <String, Object?>{
          'role': 'user',
          'content': format.appendSchema ? _promptFor(options) : options.user,
        },
      ],
    };
    final reasoning = options.reasoningEffort.trim();
    if (options.thinkingEnabled && _isReasoningModel(target.model)) {
      if (reasoning.isNotEmpty) {
        payload['reasoning_effort'] = reasoning;
      } else {
        payload['reasoning'] = <String, Object?>{
          'effort': llmDefaultReasoningEffort,
        };
      }
      payload['max_completion_tokens'] = options.maxOutputTokens;
    } else if (options.thinkingEnabled && reasoning.isNotEmpty) {
      payload['reasoning_effort'] = reasoning;
      payload['max_completion_tokens'] = options.maxOutputTokens;
    } else {
      payload['temperature'] = options.temperature;
      payload['max_tokens'] = options.maxOutputTokens;
    }
    if (format.responseFormat != null) {
      payload['response_format'] = format.responseFormat;
    }
    return payload;
  }

  String _promptFor(LlmCallOptions options) {
    final schema = options.schema;
    if (schema == null) return options.user;
    return '${options.user}\n\nJSON Schema:\n${jsonEncode(schema)}';
  }

  List<_OpenAiFormat> _openAiFormats(Map<String, Object?>? schema) {
    if (schema == null) {
      return const <_OpenAiFormat>[
        _OpenAiFormat(responseFormat: null, appendSchema: false),
      ];
    }
    return <_OpenAiFormat>[
      _OpenAiFormat(
        responseFormat: <String, Object?>{
          'type': 'json_schema',
          'json_schema': <String, Object?>{
            'name': llmJsonSchemaName,
            'strict': true,
            'schema': schema,
          },
        },
        appendSchema: false,
      ),
      const _OpenAiFormat(
        responseFormat: <String, Object?>{'type': 'json_object'},
        appendSchema: true,
      ),
      const _OpenAiFormat(responseFormat: null, appendSchema: true),
    ];
  }

  bool _shouldRetryWithoutThinking(HttpFetchResponse response) {
    if (response.statusCode != httpBadRequestStatus) return false;
    final body = response.body.toLowerCase();
    for (final keyword in llmThinkingRejectionKeywords) {
      if (body.contains(keyword.toLowerCase())) return true;
    }
    return false;
  }

  Future<HttpFetchResponse> _post(
    LlmTarget target,
    String path,
    Map<String, Object?> body,
  ) => _send(
    () => _fetcher.post(
      '${target.baseUrl}$path',
      body: jsonEncode(body),
      timeout: Duration(milliseconds: target.timeoutMs),
      headers: _headers(target),
    ),
  );

  Future<HttpFetchResponse> _send(
    Future<HttpFetchResponse> Function() request,
  ) async {
    try {
      return await request();
    } on HttpFailure catch (error) {
      if (error.kind == HttpFailureKind.timeout) {
        throw const ExternalServiceError(
          AppErrorCode.aiTimeout,
          isTransient: true,
          details: 'AI 请求超时',
        );
      }
      throw ExternalServiceError(
        AppErrorCode.aiRequestFailed,
        isTransient: true,
        details: '网络不可用：${error.detail}',
      );
    }
  }
}

/// 输出被截断的结束原因。
const String _lengthFinishReason = 'length';

Map<String, String> _headers(LlmTarget target) =>
    target.apiType == LlmApiType.anthropic
    ? <String, String>{
        'content-type': 'application/json',
        'x-api-key': target.apiKey,
        'anthropic-version': anthropicVersionHeader,
      }
    : <String, String>{
        'content-type': 'application/json',
        'authorization': 'Bearer ${target.apiKey}',
      };

bool _isReasoningModel(String model) {
  final lower = model.trim().toLowerCase();
  for (final prefix in llmReasoningModelPrefixes) {
    if (lower.startsWith(prefix)) return true;
  }
  return false;
}

ExternalServiceError _httpError(HttpFetchResponse response) {
  final status = response.statusCode;
  final transient =
      transientHttpStatusCodes.contains(status) ||
      status >= transientServerErrorFloor;
  return ExternalServiceError(
    AppErrorCode.aiRequestFailed,
    isTransient: transient,
    details: 'HTTP $status ${_snippet(response.body)}',
  );
}

ExternalServiceError _emptyResponse() => const ExternalServiceError(
  AppErrorCode.aiEmptyResponse,
  isTransient: true,
  details: '模型返回空内容',
);

ExternalServiceError _truncationError() => const ExternalServiceError(
  AppErrorCode.aiOutputTruncated,
  details: 'AI 输出被截断（达到 max_tokens 上限）',
);

ExternalServiceError _refusalError(String refusal) => ExternalServiceError(
  AppErrorCode.aiRequestFailed,
  details:
      '模型拒绝回答：${refusal.length > llmErrorSnippetChars ? refusal.substring(0, llmErrorSnippetChars) : refusal}',
);

Object? _decodeBody(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// 校验响应体确实是模型响应。
///
/// 把 `baseUrl` 配成控制台地址（缺 `/v1`）时会拿到 200 + HTML，
/// 这是配置问题、重试无意义，必须给出明确原因。
void _assertModelBody(Object? body, String raw, LlmApiType apiType) {
  final embedded = _embeddedError(body);
  if (embedded != null) {
    throw ExternalServiceError(
      AppErrorCode.aiRequestFailed,
      details: 'AI 网关返回错误：$embedded',
    );
  }
  if (body is! Map) {
    throw ExternalServiceError(
      AppErrorCode.aiRequestFailed,
      details: 'AI 网关返回了非模型响应（${_snippet(raw)}）',
    );
  }
  final hasChoices = body['choices'] is List;
  final hasContent = body['content'] is List;
  if (apiType == LlmApiType.openai && !hasChoices) {
    throw ExternalServiceError(
      AppErrorCode.aiRequestFailed,
      details: 'AI 网关返回了非模型响应（缺少 choices）',
    );
  }
  if (apiType == LlmApiType.anthropic && !hasContent) {
    throw ExternalServiceError(
      AppErrorCode.aiRequestFailed,
      details: 'AI 网关返回了非模型响应（缺少 content）',
    );
  }
}

/// 兼容网关把错误包在 200 响应体里的写法。
String? _embeddedError(Object? body) {
  if (body is! Map) return null;
  final error = body['error'];
  if (error is String && error.trim().isNotEmpty) {
    return _snippet(error.trim());
  }
  if (error is Map) {
    final message = error['message'];
    if (message is String && message.trim().isNotEmpty) {
      return _snippet(message.trim());
    }
  }
  return null;
}

String? _openAiRefusal(Object? body) {
  if (body is! Map) return null;
  final choices = body['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final choice = choices.first;
  if (choice is! Map) return null;
  final message = choice['message'];
  if (message is! Map) return null;
  final refusal = message['refusal'];
  return refusal is String && refusal.trim().isNotEmpty ? refusal.trim() : null;
}

LlmCompletion _parseOpenAi(Object? body, LlmTarget target) {
  final record = body is Map
      ? body.cast<String, Object?>()
      : const <String, Object?>{};
  final choices = record['choices'];
  final choice = choices is List && choices.isNotEmpty && choices.first is Map
      ? (choices.first as Map).cast<String, Object?>()
      : const <String, Object?>{};
  final message = choice['message'];
  final content = message is Map ? message['content'] : null;
  final usage = record['usage'];
  final usageRecord = usage is Map
      ? usage.cast<String, Object?>()
      : const <String, Object?>{};
  final finishReason = choice['finish_reason'];
  return LlmCompletion(
    text: _contentText(content).trim(),
    providerId: target.providerId,
    model: target.model,
    inputTokens: _asInt(usageRecord['prompt_tokens']),
    outputTokens: _asInt(usageRecord['completion_tokens']),
    finishReason: finishReason is String && finishReason.isNotEmpty
        ? finishReason
        : null,
  );
}

LlmCompletion _parseAnthropic(Object? body, LlmTarget target) {
  final record = body is Map
      ? body.cast<String, Object?>()
      : const <String, Object?>{};
  final content = record['content'];
  final buffer = StringBuffer();
  if (content is List) {
    for (final item in content) {
      if (item is! Map) continue;
      if (item['type'] != 'text') continue;
      buffer.write(_partText(item));
    }
  }
  final usage = record['usage'];
  final usageRecord = usage is Map
      ? usage.cast<String, Object?>()
      : const <String, Object?>{};
  final stopReason = record['stop_reason'];
  return LlmCompletion(
    text: buffer.toString().trim(),
    providerId: target.providerId,
    model: target.model,
    inputTokens: _asInt(usageRecord['input_tokens']),
    outputTokens: _asInt(usageRecord['output_tokens']),
    finishReason: stopReason is String ? stopReason : null,
  );
}

/// OpenAI 的 `content` 可能是字符串、文本块数组，也可能是被包裹的对象。
String _contentText(Object? content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      buffer.write(_partText(item));
    }
    return buffer.toString();
  }
  if (content is Map) return jsonEncode(content);
  return '';
}

String _partText(Object? item) {
  if (item is String) return item;
  if (item is! Map) return '';
  final text = item['text'];
  if (text is String) return text;
  if (text is Map) {
    final value = text['value'] ?? text['content'];
    if (value is String) return value;
  }
  return '';
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;

String _snippet(String value) {
  final collapsed = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.length > llmErrorSnippetChars
      ? collapsed.substring(0, llmErrorSnippetChars)
      : collapsed;
}
