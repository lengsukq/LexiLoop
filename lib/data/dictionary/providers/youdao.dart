/// 有道词典 provider。
///
/// 对应旧版 `modules/dictionary/providers/youdao.ts`。
///
/// **双端点**：`dict.youdao.com` 与 `www.youdao.com/result` 结构不同但字段
/// 互补，旧版并发请求两者再择优合并；单词以 `dict.` 为主，短语/句子以
/// `result` 为主（后者有「有道翻译」直译块）。
///
/// **重试**：单端点在超时/网络错误时重试一次，间隔取
/// `youdaoRetryJitterMinMs`–`youdaoRetryJitterMaxMs` 的随机抖动——
/// 两个端点同时被限流时固定间隔会持续撞在同一时刻。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/merge_content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_parser.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 一个端点的定义。
class _Endpoint {
  const new(this.id, this.buildUrl);

  final String id;
  final String Function(String term) buildUrl;
}

/// 有道的两个端点。
final List<_Endpoint> _endpoints = <_Endpoint>[
  _Endpoint(
    'dict.youdao.com',
    (term) => 'https://dict.youdao.com/w/eng/${Uri.encodeComponent(term)}',
  ),
  _Endpoint(
    'youdao.com/result',
    (term) =>
        'https://www.youdao.com/result?word=${Uri.encodeComponent(term)}'
        '&lang=en',
  ),
];

/// 单次端点调用的结果。
class _EndpointAttempt {
  const new({
    required this.endpoint,
    required this.status,
    this.fields,
    this.statusCode,
    this.errorCode,
    this.errorMessage,
  });

  final String endpoint;
  final ProviderAttemptStatus status;
  final Map<String, Object?>? fields;
  final int? statusCode;
  final String? errorCode;
  final String? errorMessage;

  /// 该次失败是否属于「退避后可重试」。
  bool get isTransient {
    if (errorCode == 'TIMEOUT' || errorCode == 'NETWORK_ERROR') return true;
    final code = statusCode;
    return code != null && code >= 500;
  }

  /// 是否值得原样重试一次。
  bool get isRetryable =>
      errorCode == 'TIMEOUT' || errorCode == 'NETWORK_ERROR';

  Map<String, Object?> toMetadata() => <String, Object?>{
    'endpoint': endpoint,
    'status': status.wire,
    if (statusCode != null) 'statusCode': statusCode,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
}

/// 有道端点调用的汇总。
class _EndpointOutcome {
  const new(this.endpoint, this.attempts);

  final String endpoint;
  final List<_EndpointAttempt> attempts;

  Map<String, Object?>? get fields {
    for (final attempt in attempts) {
      if (attempt.fields != null) return attempt.fields;
    }
    return null;
  }
}

/// 有道词典 provider。
class YoudaoProvider implements DictionaryProvider {
  /// 以 HTTP 客户端、随机源与等待函数构造。
  ///
  /// [random] 与 [sleep] 可注入，使「重试一次 + 抖动」在单测中确定且不真的等待。
  new(
    this._fetcher, {
    math.Random? random,
    Future<void> Function(Duration duration)? sleep,
  }) : _random = random ?? math.Random(),
       _sleep = sleep ?? Future<void>.delayed;

  final HttpFetcher _fetcher;
  final math.Random _random;
  final Future<void> Function(Duration duration) _sleep;

  @override
  String get id => 'youdao';

  @override
  Set<String> get providedFields => providerCapabilities['youdao']!;

  @override
  bool isEnabled(AppSettings settings) => settings.providers.youdaoEnabled;

  @override
  bool supports(ProviderRequest request) =>
      request.sourceLanguage.toLowerCase().startsWith('en');

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    final isWord = request.contentType == LexicalContentType.word;
    final primary = isWord ? _endpoints[0] : _endpoints[1];
    final secondary = isWord ? _endpoints[1] : _endpoints[0];
    final outcomes = await Future.wait(<Future<_EndpointOutcome>>[
      _lookupWithRetry(primary, request),
      _lookupWithRetry(secondary, request),
    ]);
    final attempts = <_EndpointAttempt>[
      for (final outcome in outcomes) ...outcome.attempts,
    ];
    final candidates = <_EndpointOutcome>[
      for (final outcome in outcomes)
        if (outcome.fields != null && hasAnyYoudaoContent(outcome.fields!))
          outcome,
    ];
    if (candidates.isEmpty) return _emptyOrThrow(attempts);
    candidates.sort(
      (left, right) => _scoreContent(
        right.fields!,
        request,
      ).compareTo(_scoreContent(left.fields!, request)),
    );
    final best = candidates.first;
    final fields = candidates.length > 1
        ? mergeContentFields(<Map<String, Object?>?>[
            best.fields,
            candidates[1].fields,
          ])
        : best.fields!;
    return ProviderResult(
      fields: fields,
      providerId: id,
      qualityScore: _scoreContent(fields, request).clamp(0, 100),
      metadata: <String, Object?>{
        'sourceEndpoint': best.endpoint,
        'fallbackUsed': candidates.length > 1 || best.endpoint != primary.id,
        'endpointAttempts': <Object?>[
          for (final attempt in attempts) attempt.toMetadata(),
        ],
      },
    );
  }

  /// 全部端点都没有可用内容时：都算「空」就返回 `null`，否则抛错。
  ProviderResult? _emptyOrThrow(List<_EndpointAttempt> attempts) {
    final failures = <_EndpointAttempt>[
      for (final attempt in attempts)
        if (attempt.status == ProviderAttemptStatus.failed) attempt,
    ];
    if (failures.isEmpty) return null;
    final detail = attempts.map(_describeAttempt).join('; ');
    final transient = failures.any((attempt) => attempt.isTransient);
    throw ExternalServiceError(
      transient
          ? AppErrorCode.providerTransientFailure
          : AppErrorCode.requestedFieldsEmpty,
      isTransient: transient,
      details: detail,
    );
  }

  Future<_EndpointOutcome> _lookupWithRetry(
    _Endpoint endpoint,
    ProviderRequest request,
  ) async {
    final first = await _lookupEndpoint(endpoint, request);
    if (first.fields != null || !first.isRetryable) {
      return _EndpointOutcome(endpoint.id, <_EndpointAttempt>[first]);
    }
    await _sleep(_jitter());
    final second = await _lookupEndpoint(endpoint, request);
    return _EndpointOutcome(endpoint.id, <_EndpointAttempt>[first, second]);
  }

  Duration _jitter() => Duration(
    milliseconds:
        youdaoRetryJitterMinMs +
        _random.nextInt(youdaoRetryJitterMaxMs - youdaoRetryJitterMinMs),
  );

  Future<_EndpointAttempt> _lookupEndpoint(
    _Endpoint endpoint,
    ProviderRequest request,
  ) async {
    try {
      final response = await _fetcher.get(
        endpoint.buildUrl(request.term),
        timeout: const Duration(milliseconds: dictionaryProviderTimeoutMs),
        headers: _headers,
      );
      if (!response.isSuccess) {
        return _EndpointAttempt(
          endpoint: endpoint.id,
          status: ProviderAttemptStatus.failed,
          statusCode: response.statusCode,
          errorCode: 'HTTP_${response.statusCode}',
          errorMessage: '页面返回 ${response.statusCode}',
        );
      }
      final fields = parseYoudaoHtml(
        response.body,
        term: request.term,
        contentType: request.contentType,
        targetLanguage: request.targetLanguage,
      );
      if (fields == null || !hasAnyYoudaoContent(fields)) {
        final hasBody = response.body.trim().isNotEmpty;
        return _EndpointAttempt(
          endpoint: endpoint.id,
          status: ProviderAttemptStatus.empty,
          statusCode: response.statusCode,
          errorCode: hasBody ? 'UNPARSABLE_RESPONSE' : 'EMPTY_RESPONSE',
          errorMessage: hasBody ? '页面存在内容，但未解析出词典字段' : '页面内容为空',
        );
      }
      return _EndpointAttempt(
        endpoint: endpoint.id,
        status: ProviderAttemptStatus.success,
        fields: fields,
        statusCode: response.statusCode,
      );
    } on HttpFailure catch (error) {
      final timeout = error.kind == HttpFailureKind.timeout;
      return _EndpointAttempt(
        endpoint: endpoint.id,
        status: ProviderAttemptStatus.failed,
        errorCode: timeout ? 'TIMEOUT' : 'NETWORK_ERROR',
        errorMessage: timeout ? '请求超时' : '网络不可用',
      );
    }
  }
}

/// 请求头。
const Map<String, String> _headers = <String, String>{
  'accept': 'text/html,application/xhtml+xml',
  'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'cache-control': 'no-cache',
  'user-agent': 'Mozilla/5.0 LexiLoop',
};

/// 有道的字段完整度打分（越高越饱满）。
int _scoreContent(Map<String, Object?> fields, ProviderRequest request) {
  if (_satisfiesRequestedFields(fields, request)) return _satisfiedScore;
  if (!hasAnyYoudaoContent(fields)) return 0;
  var score = 0;
  score += _length(fields, 'definitions') * 5;
  score += _length(fields, 'examples') * 3;
  score += _length(fields, 'phrases') * 2;
  score += _length(fields, 'pronunciations') * 4;
  score += _length(fields, 'synonyms');
  score += _length(fields, 'wordFamily');
  final summary = fields['summary'];
  if (summary is Map) {
    if (_nonEmpty(summary['translation'])) score += 8;
    if (_nonEmpty(summary['shortDefinition'])) score += 4;
  }
  return score;
}

/// 满足全部请求字段时的满分（远高于任何内容累加分）。
const int _satisfiedScore = 1000;

int _length(Map<String, Object?> fields, String field) {
  final value = fields[field];
  return value is List ? value.length : 0;
}

bool _nonEmpty(Object? value) => value is String && value.trim().isNotEmpty;

bool _satisfiesRequestedFields(
  Map<String, Object?> fields,
  ProviderRequest request,
) {
  final requested = <String>[
    for (final field in request.wantedFields)
      if (providerCapabilities['youdao']!.contains(field)) field,
  ];
  if (requested.isEmpty) {
    switch (request.contentType) {
      case LexicalContentType.sentence:
        final summary = fields['summary'];
        return (summary is Map && _nonEmpty(summary['translation'])) ||
            _length(fields, 'definitions') > 0 ||
            _length(fields, 'examples') > 0;
      case LexicalContentType.phrase:
        return _length(fields, 'definitions') > 0 ||
            _length(fields, 'phrases') > 0;
      case LexicalContentType.word:
        return _length(fields, 'definitions') > 0 ||
            _length(fields, 'pronunciations') > 0;
    }
  }
  for (final field in requested) {
    if (!_hasField(fields, field)) return false;
  }
  return true;
}

bool _hasField(Map<String, Object?> fields, String field) {
  switch (field) {
    case 'definitions':
      return _length(fields, 'definitions') > 0;
    case 'pronunciations.phonetic':
    case 'pronunciations.audio':
      return _hasPronunciation(fields, field);
    case 'summary':
      final summary = fields['summary'];
      return summary is Map &&
          (_nonEmpty(summary['translation']) ||
              _nonEmpty(summary['shortDefinition']));
    case 'examples':
    case 'phrases':
    case 'forms':
    case 'synonyms':
    case 'antonyms':
    case 'wordFamily':
    case 'roots':
    case 'affixes':
    case 'tags':
      return _length(fields, field) > 0;
    default:
      return false;
  }
}

bool _hasPronunciation(Map<String, Object?> fields, String field) {
  final value = fields['pronunciations'];
  if (value is! List) return false;
  final wantsAudio = field == 'pronunciations.audio';
  for (final item in value) {
    if (item is! Map) continue;
    if (wantsAudio && _nonEmpty(item['audioUrl'])) return true;
    if (!wantsAudio && _nonEmpty(item['phonetic'])) return true;
  }
  return false;
}

/// 把一次端点尝试描述成 `端点: 错误码 (说明)`。
String _describeAttempt(_EndpointAttempt attempt) {
  final code = attempt.errorCode ?? attempt.status.wire;
  final message = attempt.errorMessage;
  return '${attempt.endpoint}: $code${message == null ? '' : ' ($message)'}';
}
