/// MyMemory 翻译 provider。
///
/// 对应旧版 `modules/dictionary/providers/mymemory.ts`。
/// 免费、无需 Key，用作「主数据源都没有释义」时的兜底译文。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// MyMemory 支持的语言代码。
const Set<String> myMemorySupportedLanguages = <String>{
  'en',
  'zh-CN',
  'zh-TW',
  'nl',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
  'it',
  'pt',
  'ru',
};

/// 备用译文的最低匹配度。
const double _minMatchScore = 0.85;

/// 最多返回的译文条数。
const int _maxTranslations = 4;

/// 限流状态码。
const int _rateLimitedStatus = 429;

/// MyMemory 翻译 provider。
class MyMemoryProvider implements DictionaryProvider {
  /// 以 HTTP 客户端构造。
  const new(this._fetcher);

  final HttpFetcher _fetcher;

  @override
  String get id => 'mymemory';

  @override
  Set<String> get providedFields => providerCapabilities['mymemory']!;

  @override
  bool isEnabled(AppSettings settings) => settings.providers.myMemoryEnabled;

  @override
  bool supports(ProviderRequest request) =>
      myMemorySupportedLanguages.contains(request.sourceLanguage) &&
      myMemorySupportedLanguages.contains(request.targetLanguage);

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    final response = await _get(request);
    if (!response.isSuccess) {
      final transient =
          response.statusCode == _rateLimitedStatus ||
          response.statusCode >= transientServerErrorFloor;
      throw ExternalServiceError(
        transient
            ? AppErrorCode.providerTransientFailure
            : AppErrorCode.requestedFieldsEmpty,
        isTransient: transient,
        details: '翻译服务返回 ${response.statusCode}',
      );
    }
    final translations = _translations(response.body, request.term);
    if (translations.isEmpty) return null;
    return ProviderResult(
      fields: <String, Object?>{
        'definitions': <Map<String, Object?>>[
          for (final text in translations)
            <String, Object?>{
              'language': request.targetLanguage,
              'partOfSpeech': null,
              'text': text,
              'source': id,
              'isUserEdited': false,
            },
        ],
      },
      providerId: id,
      qualityScore: _qualityScore(translations.length),
    );
  }

  Future<HttpFetchResponse> _get(ProviderRequest request) async {
    final url =
        'https://api.mymemory.translated.net/get'
        '?q=${Uri.encodeComponent(request.term)}'
        '&langpair=${Uri.encodeComponent(request.sourceLanguage)}'
        '%7C${Uri.encodeComponent(request.targetLanguage)}';
    try {
      return await _fetcher.get(
        url,
        timeout: const Duration(milliseconds: translationProviderTimeoutMs),
        headers: const <String, String>{'user-agent': 'LexiLoop/1.0'},
      );
    } on HttpFailure catch (error) {
      throw ExternalServiceError(
        AppErrorCode.providerTransientFailure,
        isTransient: true,
        details: error.kind == HttpFailureKind.timeout ? '请求超时' : '网络不可用',
      );
    }
  }
}

/// 从响应体里取出译文列表（主译文 + 高匹配度备用译文）。
List<String> _translations(String body, String term) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const <String>[];
  }
  if (decoded is! Map) return const <String>[];
  final primary = _translatedText(decoded['responseData']);
  if (primary.isEmpty || primary.toLowerCase() == term.toLowerCase()) {
    return const <String>[];
  }
  final values = <String>[primary];
  final matches = decoded['matches'];
  if (matches is List) {
    for (final item in matches) {
      if (item is! Map) continue;
      final score = item['match'];
      if (score is! num || score.toDouble() < _minMatchScore) continue;
      final text = _translatedText(item);
      if (text.isNotEmpty) values.add(text);
    }
  }
  final unique = <String>[];
  for (final value in values) {
    if (!unique.contains(value)) unique.add(value);
    if (unique.length >= _maxTranslations) break;
  }
  return unique;
}

String _translatedText(Object? raw) {
  if (raw is! Map) return '';
  final value = raw['translatedText'] ?? raw['translation'];
  return value is String ? value.trim() : '';
}

int _qualityScore(int count) {
  final score = count * 12;
  return score > 100 ? 100 : score;
}
