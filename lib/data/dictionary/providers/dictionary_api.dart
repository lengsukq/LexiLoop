/// dictionaryapi.dev provider。
///
/// 对应旧版 `modules/dictionary/providers/dictionary-api.ts`。
/// 纯 JSON 接口、无需 API Key，是英文单词最稳的兜底来源。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// dictionaryapi.dev provider。
class DictionaryApiProvider implements DictionaryProvider {
  /// 以 HTTP 客户端构造。
  const new(this._fetcher);

  final HttpFetcher _fetcher;

  @override
  String get id => 'dictionaryapi.dev';

  @override
  Set<String> get providedFields => providerCapabilities['dictionaryapi.dev']!;

  @override
  bool isEnabled(AppSettings settings) =>
      settings.providers.dictionaryApiEnabled;

  @override
  bool supports(ProviderRequest request) =>
      request.sourceLanguage == 'en' &&
      request.contentType == LexicalContentType.word;

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    final response = await _get(request.term);
    if (response.statusCode == _notFoundStatus) return null;
    if (!response.isSuccess) {
      final transient =
          response.statusCode == _rateLimitedStatus ||
          response.statusCode >= transientServerErrorFloor;
      throw ExternalServiceError(
        transient
            ? AppErrorCode.providerTransientFailure
            : AppErrorCode.requestedFieldsEmpty,
        isTransient: transient,
        details: '词典 API 返回 ${response.statusCode}',
      );
    }
    final fields = _parse(response.body);
    if (fields == null) return null;
    return ProviderResult(
      fields: fields,
      providerId: id,
      qualityScore: _qualityScore(fields),
    );
  }

  Future<HttpFetchResponse> _get(String term) async {
    try {
      return await _fetcher.get(
        'https://api.dictionaryapi.dev/api/v2/entries/en/'
        '${Uri.encodeComponent(term)}',
        timeout: const Duration(milliseconds: dictionaryProviderTimeoutMs),
        headers: const <String, String>{
          'accept': 'application/json',
          'user-agent': 'LexiLoop/1.0',
        },
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

/// 词条不存在的状态码。
const int _notFoundStatus = 404;

/// 限流的状态码。
const int _rateLimitedStatus = 429;

/// 最多读取的条目数。
const int _maxEntries = 2;

Map<String, Object?>? _parse(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final definitions = <Map<String, Object?>>[];
  final pronunciations = <Map<String, Object?>>[];
  final examples = <Map<String, Object?>>[];
  final synonyms = <Map<String, Object?>>[];
  final antonyms = <Map<String, Object?>>[];
  var count = 0;
  for (final entry in decoded) {
    if (count >= _maxEntries) break;
    if (entry is! Map) continue;
    count += 1;
    _appendEntry(
      entry.cast<String, Object?>(),
      definitions: definitions,
      pronunciations: pronunciations,
      examples: examples,
      synonyms: synonyms,
      antonyms: antonyms,
    );
  }
  if (definitions.isEmpty) return null;
  return <String, Object?>{
    'definitions': definitions,
    'pronunciations': pronunciations,
    'examples': examples,
    'synonyms': synonyms,
    'antonyms': antonyms,
    'tags': const <String>[],
  };
}

void _appendEntry(
  Map<String, Object?> entry, {
  required List<Map<String, Object?>> definitions,
  required List<Map<String, Object?>> pronunciations,
  required List<Map<String, Object?>> examples,
  required List<Map<String, Object?>> synonyms,
  required List<Map<String, Object?>> antonyms,
}) {
  final fallbackPhonetic = entry['phonetic'];
  for (final raw in _list(entry['phonetics'])) {
    final record = _map(raw);
    final text = _string(record['text']).trim();
    final audio = _string(record['audio']).trim();
    if (text.isEmpty && audio.isEmpty) continue;
    final marker = '$audio ${_string(record['sourceUrl'])}'.toLowerCase();
    pronunciations.add(<String, Object?>{
      'accent': marker.contains('uk') ? 'UK' : 'US',
      'phonetic': text.isEmpty ? fallbackPhonetic : text,
      'audioUrl': audio.isEmpty ? null : audio,
      'source': 'dictionaryapi.dev',
      'isSynthetic': false,
    });
  }
  for (final raw in _list(entry['meanings'])) {
    _appendMeaning(
      _map(raw),
      definitions: definitions,
      examples: examples,
      synonyms: synonyms,
      antonyms: antonyms,
    );
  }
}

void _appendMeaning(
  Map<String, Object?> meaning, {
  required List<Map<String, Object?>> definitions,
  required List<Map<String, Object?>> examples,
  required List<Map<String, Object?>> synonyms,
  required List<Map<String, Object?>> antonyms,
}) {
  final partOfSpeech = _string(meaning['partOfSpeech']).trim();
  final pos = partOfSpeech.isEmpty ? null : partOfSpeech;
  for (final raw in _list(meaning['definitions'])) {
    final record = _map(raw);
    final text = _string(record['definition']).trim();
    if (text.isEmpty) continue;
    definitions.add(<String, Object?>{
      'language': 'en',
      'partOfSpeech': pos,
      'text': text,
      'source': 'dictionaryapi.dev',
      'isUserEdited': false,
    });
    final example = _string(record['example']).trim();
    if (example.isNotEmpty) {
      examples.add(<String, Object?>{
        'sentence': example,
        'translation': null,
        'source': 'dictionaryapi.dev',
        'isUserAdded': false,
      });
    }
    _appendWords(record['synonyms'], 'SYNONYM', pos, synonyms);
    _appendWords(record['antonyms'], 'ANTONYM', pos, antonyms);
  }
  _appendWords(meaning['synonyms'], 'SYNONYM', pos, synonyms);
  _appendWords(meaning['antonyms'], 'ANTONYM', pos, antonyms);
}

void _appendWords(
  Object? raw,
  String relation,
  String? partOfSpeech,
  List<Map<String, Object?>> target,
) {
  for (final item in _list(raw)) {
    final word = _string(item).trim();
    if (word.isEmpty) continue;
    target.add(<String, Object?>{
      'word': word,
      'translation': null,
      'partOfSpeech': partOfSpeech,
      'relation': relation,
      'source': 'dictionaryapi.dev',
      'difference': null,
    });
  }
}

int _qualityScore(Map<String, Object?> fields) {
  var score = _length(fields, 'definitions') * 8;
  score += _length(fields, 'examples') * 4;
  score += _length(fields, 'pronunciations') * 5;
  score += _length(fields, 'synonyms') * 2;
  score += _length(fields, 'antonyms') * 2;
  return score > 100 ? 100 : score;
}

int _length(Map<String, Object?> fields, String field) {
  final value = fields[field];
  return value is List ? value.length : 0;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String _string(Object? value) => value is String ? value : '';
