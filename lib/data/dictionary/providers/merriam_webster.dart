/// Merriam-Webster provider。
///
/// 对应旧版 `modules/dictionary/providers/merriam-webster.ts`。
///
/// **需要两把 Key**：`collegiate`（释义 / 音标 / 例句）与 `thesaurus`
/// （同义 / 反义）。两把 Key 独立，因此这里用「任一成功就算成功」的语义，
/// 而不是要求两者都配齐。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// Merriam-Webster 词典 Key 在 `settings.raw` 中的键名。
const String merriamWebsterDictionaryKeyName = 'merriamWebsterDictionaryKey';

/// Merriam-Webster 同义词典 Key 在 `settings.raw` 中的键名。
const String merriamWebsterThesaurusKeyName = 'merriamWebsterThesaurusKey';

/// 同义 / 反义词最多返回的条数。
const int _maxRelatedWords = 24;

/// 例句最多返回的条数。
const int _maxExamples = 6;

/// Merriam-Webster provider。
class MerriamWebsterProvider implements DictionaryProvider {
  /// 以设置与 HTTP 客户端构造。
  const new(this._settings, this._fetcher);

  final AppSettings _settings;
  final HttpFetcher _fetcher;

  /// 词典 Key。
  String get dictionaryKey => _raw(merriamWebsterDictionaryKeyName);

  /// 同义词典 Key。
  String get thesaurusKey => _raw(merriamWebsterThesaurusKeyName);

  @override
  String get id => 'merriam-webster';

  @override
  Set<String> get providedFields => providerCapabilities['merriam-webster']!;

  @override
  bool isEnabled(AppSettings settings) =>
      settings.providers.merriamWebsterEnabled &&
      (_rawKey(settings, merriamWebsterDictionaryKeyName).isNotEmpty ||
          _rawKey(settings, merriamWebsterThesaurusKeyName).isNotEmpty);

  @override
  bool supports(ProviderRequest request) =>
      request.sourceLanguage == 'en' &&
      request.contentType == LexicalContentType.word;

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    if (dictionaryKey.isEmpty && thesaurusKey.isEmpty) {
      // 明确区分「用户没开」与「开了但没配 Key」，否则用户只会看到空结果。
      throw const ExternalServiceError(
        AppErrorCode.aiConfigIncomplete,
        details: 'Merriam-Webster 需要词典或同义词典 API Key',
      );
    }
    final results = await Future.wait(<Future<_MwResponse>>[
      _request('collegiate', request.term, dictionaryKey),
      _request('thesaurus', request.term, thesaurusKey),
    ]);
    if (results.every((result) => result.error != null)) {
      throw ExternalServiceError(
        AppErrorCode.providerTransientFailure,
        isTransient: true,
        details: results.map((result) => result.error).join('; '),
      );
    }
    final dictionary = results[0].entries;
    final thesaurus = results[1].entries;
    final fields = _buildFields(dictionary, thesaurus);
    if (fields == null) return null;
    return ProviderResult(
      fields: fields,
      providerId: id,
      qualityScore: _qualityScore(fields),
    );
  }

  String _raw(String key) => _rawKey(_settings, key);

  Future<_MwResponse> _request(
    String reference,
    String term,
    String key,
  ) async {
    if (key.isEmpty) return const _MwResponse(null, null);
    final url =
        'https://www.dictionaryapi.com/api/v3/references/$reference/json/'
        '${Uri.encodeComponent(term)}?key=${Uri.encodeComponent(key)}';
    try {
      final response = await _fetcher.get(
        url,
        timeout: const Duration(milliseconds: dictionaryProviderTimeoutMs),
        headers: const <String, String>{
          'accept': 'application/json',
          'user-agent': 'LexiLoop/1.0',
        },
      );
      if (response.statusCode == 404) return const _MwResponse(null, null);
      if (!response.isSuccess) {
        return _MwResponse(null, 'HTTP_${response.statusCode}');
      }
      return _MwResponse(_entries(response.body), null);
    } on HttpFailure catch (error) {
      return _MwResponse(
        null,
        error.kind == HttpFailureKind.timeout ? 'TIMEOUT' : 'NETWORK_ERROR',
      );
    }
  }
}

/// 读取 `settings.raw` 里的字符串键。
String _rawKey(AppSettings settings, String key) {
  final value = settings.raw[key];
  return value is String ? value.trim() : '';
}

/// 单次 Merriam-Webster 调用的结果（二选一非空）。
class _MwResponse {
  const new(this.entries, this.error);

  final List<Map<String, Object?>>? entries;
  final String? error;
}

List<Map<String, Object?>>? _entries(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final result = <Map<String, Object?>>[];
  for (final item in decoded) {
    if (item is Map) result.add(item.cast<String, Object?>());
  }
  return result;
}

Map<String, Object?>? _buildFields(
  List<Map<String, Object?>>? dictionary,
  List<Map<String, Object?>>? thesaurus,
) {
  final definitions = <Map<String, Object?>>[];
  final pronunciations = <Map<String, Object?>>[];
  for (final entry in dictionary ?? const <Map<String, Object?>>[]) {
    final pos = entry['fl'];
    final partOfSpeech = pos is String ? pos : null;
    for (final raw in _list(entry['shortdef'])) {
      final text = _cleanMarkup(raw);
      if (text.isEmpty) continue;
      definitions.add(<String, Object?>{
        'language': 'en',
        'partOfSpeech': partOfSpeech,
        'text': text,
        'source': 'merriam-webster',
        'isUserEdited': false,
      });
    }
    _appendPronunciations(entry, pronunciations);
  }
  final synonyms = _words(_flattenMeta(thesaurus, 'syns'), 'SYNONYM');
  final antonyms = _words(_flattenMeta(thesaurus, 'ants'), 'ANTONYM');
  if (definitions.isEmpty && synonyms.isEmpty && antonyms.isEmpty) return null;
  return <String, Object?>{
    'definitions': definitions,
    'pronunciations': pronunciations,
    'examples': _examples(dictionary ?? const <Map<String, Object?>>[]),
    'synonyms': synonyms,
    'antonyms': antonyms,
  };
}

void _appendPronunciations(
  Map<String, Object?> entry,
  List<Map<String, Object?>> target,
) {
  final hwi = entry['hwi'];
  if (hwi is! Map) return;
  for (final raw in _list(hwi['prs'])) {
    final record = raw is Map ? raw.cast<String, Object?>() : null;
    if (record == null) continue;
    final phonetic = record['mw'];
    if (phonetic is! String || phonetic.trim().isEmpty) continue;
    final sound = record['sound'];
    final audio = sound is Map ? sound['audio'] : null;
    target.add(<String, Object?>{
      'accent': 'US',
      'phonetic': phonetic,
      'audioUrl': audio is String && audio.isNotEmpty ? _audioUrl(audio) : null,
      'source': 'merriam-webster',
      'isSynthetic': false,
    });
  }
}

List<Object?> _flattenMeta(List<Map<String, Object?>>? thesaurus, String key) {
  final result = <Object?>[];
  for (final entry in thesaurus ?? const <Map<String, Object?>>[]) {
    final meta = entry['meta'];
    if (meta is! Map) continue;
    final groups = meta[key];
    if (groups is! List) continue;
    for (final group in groups) {
      if (group is List) result.addAll(group);
    }
  }
  return result;
}

List<Map<String, Object?>> _words(List<Object?> raw, String relation) {
  final seen = <String>{};
  final result = <Map<String, Object?>>[];
  for (final item in raw) {
    final word = item is String ? item.trim() : '';
    if (word.isEmpty || !seen.add(word)) continue;
    result.add(<String, Object?>{
      'word': word,
      'translation': null,
      'partOfSpeech': null,
      'relation': relation,
      'source': 'merriam-webster',
      'difference': null,
    });
    if (result.length >= _maxRelatedWords) break;
  }
  return result;
}

List<Map<String, Object?>> _examples(List<Map<String, Object?>> entries) {
  final result = <Map<String, Object?>>[];
  for (final entry in entries) {
    _visit(entry['def'], result);
    if (result.length >= _maxExamples) break;
  }
  return result.length > _maxExamples
      ? result.sublist(0, _maxExamples)
      : result;
}

/// 递归遍历 `def.sseq`，收集 `vis`（视觉例句）节点。
void _visit(Object? value, List<Map<String, Object?>> target) {
  if (value is Map) {
    for (final child in value.values) {
      _visit(child, target);
    }
    return;
  }
  if (value is! List) return;
  for (final item in value) {
    if (item is! List) {
      _visit(item, target);
      continue;
    }
    if (item.isNotEmpty && item.first == 'vis' && item.length > 1) {
      _appendVis(item[1], target);
      continue;
    }
    _visit(item, target);
  }
}

void _appendVis(Object? raw, List<Map<String, Object?>> target) {
  if (raw is! List) return;
  for (final item in raw) {
    if (item is! Map) continue;
    final sentence = _cleanMarkup(item['t']);
    if (sentence.isEmpty) continue;
    target.add(<String, Object?>{
      'sentence': sentence,
      'translation': null,
      'source': 'merriam-webster',
      'isUserAdded': false,
    });
  }
}

/// 处理 Merriam-Webster 的 `{...}` 标记并折叠空白。
///
/// **有意偏离旧版**：旧版把整个 `{a_link|salutation}` 删掉，于是
/// `shortdef` 里就留下一条空文本释义，只能靠下游过滤。MW 的约定是
/// `{标签|显示文本}`，因此这里保留 `|` 之后的部分，标记本身才丢弃。
String _cleanMarkup(Object? value) {
  final text = value is String ? value : '';
  return text
      .replaceAllMapped(RegExp(r'\{([^}]*)\}'), (match) {
        final parts = match.group(1)!.split('|');
        return parts.length > 1 ? parts[1] : '';
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _audioUrl(String audio) {
  final first = audio.isEmpty ? '' : audio.substring(0, 1).toLowerCase();
  final String folder;
  if (audio.startsWith('bix')) {
    folder = 'bix';
  } else if (audio.startsWith('gg')) {
    folder = 'gg';
  } else if (RegExp('[^a-z]').hasMatch(first)) {
    folder = 'number';
  } else {
    folder = first;
  }
  return 'https://media.merriam-webster.com/audio/prons/en/us/mp3/'
      '$folder/$audio.mp3';
}

int _qualityScore(Map<String, Object?> fields) {
  var score = _length(fields, 'definitions') * 10;
  score += _length(fields, 'pronunciations') * 6;
  score += _length(fields, 'examples') * 4;
  score += _length(fields, 'synonyms') * 2;
  score += _length(fields, 'antonyms') * 2;
  return score > 100 ? 100 : score;
}

int _length(Map<String, Object?> fields, String field) {
  final value = fields[field];
  return value is List ? value.length : 0;
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];
