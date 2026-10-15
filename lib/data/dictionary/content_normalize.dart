/// 词条内容的归一化。
///
/// 对应旧版 `modules/dictionary/content.ts` 的 `normalizeDictionaryContent`
/// 与 `dictionaryContentFromRow`。
///
/// **为什么必须归一化**：内容有两个来源——provider 的 `fields` 与数据库的
/// `*_json` 列，两者都可能是脏数据（缺键、类型不符、空文本）。若不在这里
/// 收敛，合并管线、判题与展示各自都要做一次防御性判断，旧版因此出现了
/// 六份「取目标语言释义文本」的重复实现。
library;

import 'dart:convert';

import 'package:lexiloop/data/dictionary/content.dart';

/// 归一化任意来源的内容。
///
/// 缺失字段补默认值，类型不符的条目被丢弃，空文本被剔除。
DictionaryContent normalizeDictionaryContent(Map<String, Object?>? raw) {
  final source = raw ?? const <String, Object?>{};
  return DictionaryContent(<String, Object?>{
    'definitions': _normalizeDefinitions(source['definitions']),
    'pronunciations': _normalizePronunciations(source['pronunciations']),
    'examples': _normalizeExamples(source['examples']),
    'phrases': _normalizePhrases(source['phrases']),
    'forms': _normalizeForms(source['forms']),
    'synonyms': _normalizeRelated(source['synonyms'], 'SYNONYM'),
    'antonyms': _normalizeRelated(source['antonyms'], 'ANTONYM'),
    'wordFamily': _normalizeRelated(source['wordFamily'], 'WORD_FAMILY'),
    'confusedWords': _normalizeRelated(
      source['confusedWords'],
      'CONFUSED_WITH',
    ),
    'roots': _normalizeRoots(source['roots']),
    'affixes': _normalizeAffixes(source['affixes']),
    'summary': _normalizeSummary(source['summary']),
    'learning': _normalizeLearning(source['learning']),
    'sentenceAnalysis': _normalizeSentenceAnalysis(source['sentenceAnalysis']),
    'tags': _normalizeStrings(source['tags']),
  });
}

/// 从 `word_contents` 的一行构造内容。
///
/// 列名由 [contentColumnNames] 决定；单个列损坏只影响该字段。
DictionaryContent dictionaryContentFromColumns(Map<String, Object?> row) {
  final fields = <String, Object?>{};
  for (final entry in contentColumnNames.entries) {
    fields[entry.key] = _decodeColumn(row[entry.value]);
  }
  return normalizeDictionaryContent(fields);
}

/// 把 `DictionaryContent` 转回可被 [normalizeDictionaryContent] 消费的映射。
Map<String, Object?> contentToRaw(DictionaryContent content) => content.fields;

List<Map<String, Object?>> _normalizeDefinitions(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final text = _clean(item['text']);
    if (text.isEmpty) continue;
    result.add(<String, Object?>{
      'language': _clean(item['language']),
      'text': text,
      'partOfSpeech': _nullable(item['partOfSpeech']),
      'source': _nullable(item['source']),
      'isUserEdited': item['isUserEdited'] == true,
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizePronunciations(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final phonetic = _clean(item['phonetic']);
    if (phonetic.isEmpty) continue;
    result.add(<String, Object?>{
      'accent': item['accent'] == 'UK' ? 'UK' : 'US',
      'phonetic': phonetic,
      'audioUrl': _nullable(item['audioUrl']),
      'source': _nullable(item['source']),
      'isSynthetic': item['isSynthetic'] == true,
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeExamples(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final sentence = _clean(item['sentence']);
    if (sentence.isEmpty) continue;
    result.add(<String, Object?>{
      'sentence': sentence,
      'translation': _nullable(item['translation']),
      'source': _nullable(item['source']),
      'isUserAdded': item['isUserAdded'] == true,
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizePhrases(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final phrase = _clean(item['phrase']);
    if (phrase.isEmpty) continue;
    result.add(<String, Object?>{
      'phrase': phrase,
      'translation': _nullable(item['translation']),
      'source': _nullable(item['source']),
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeForms(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final formValue = _clean(item['value']);
    final type = _clean(item['type']);
    if (formValue.isEmpty || type.isEmpty) continue;
    result.add(<String, Object?>{
      'type': type,
      'value': formValue,
      'source': _nullable(item['source']),
    });
  }
  return result;
}

/// 关联词（同义词 / 反义词 / 同根词 / 易混词）归一化。
///
/// 接受纯字符串条目——旧版 provider 有直接产出 `string[]` 的历史数据。
List<Map<String, Object?>> _normalizeRelated(Object? value, String relation) {
  final result = <Map<String, Object?>>[];
  final raw = value;
  if (raw is! List) return result;
  for (final item in raw) {
    if (item is String) {
      final word = item.trim();
      if (word.isEmpty) continue;
      result.add(<String, Object?>{
        'word': word,
        'translation': null,
        'partOfSpeech': null,
        'relation': relation,
        'source': null,
        'difference': null,
      });
      continue;
    }
    if (item is! Map) continue;
    final record = item.cast<String, Object?>();
    final word = _clean(record['word']);
    if (word.isEmpty) continue;
    result.add(<String, Object?>{
      'word': word,
      'translation': _nullable(record['translation']),
      'partOfSpeech': _nullable(record['partOfSpeech']),
      'relation': _clean(record['relation']).isEmpty
          ? relation
          : _clean(record['relation']),
      'source': _nullable(record['source']),
      'difference': _nullable(record['difference']),
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeRoots(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final root = _clean(item['root']);
    final meaning = _clean(item['meaning']);
    if (root.isEmpty || meaning.isEmpty) continue;
    result.add(<String, Object?>{
      'root': root,
      'meaning': meaning,
      'origin': _nullable(item['origin']),
      'source': _nullable(item['source']),
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeAffixes(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final affixValue = _clean(item['value']);
    final meaning = _clean(item['meaning']);
    final type = item['type'] == 'PREFIX'
        ? 'PREFIX'
        : item['type'] == 'SUFFIX'
        ? 'SUFFIX'
        : '';
    if (affixValue.isEmpty || meaning.isEmpty || type.isEmpty) continue;
    result.add(<String, Object?>{
      'value': affixValue,
      'meaning': meaning,
      'type': type,
      'source': _nullable(item['source']),
    });
  }
  return result;
}

Map<String, Object?> _normalizeSummary(Object? value) {
  final record = _map(value);
  return <String, Object?>{
    'shortDefinition': _nullable(record['shortDefinition']),
    'translation': _nullable(record['translation']),
    'cefrLevel': record['cefrLevel'],
    'frequency': record['frequency'],
  };
}

Map<String, Object?> _normalizeLearning(Object? value) {
  final record = _map(value);
  return <String, Object?>{
    'pronunciationTip': _nullable(record['pronunciationTip']),
    'mnemonic': _nullable(record['mnemonic']),
    'commonMistakes': _normalizeStrings(record['commonMistakes']),
  };
}

Map<String, Object?> _normalizeSentenceAnalysis(Object? value) {
  final record = _map(value);
  return <String, Object?>{
    'grammarPattern': _nullable(record['grammarPattern']),
    'grammarExplanation': _nullable(record['grammarExplanation']),
    'grammarNotes': _normalizeStrings(record['grammarNotes']),
    'keyExpressions': _normalizeKeyExpressions(record['keyExpressions']),
    'similarExamples': _normalizeSimilarExamples(record['similarExamples']),
    'variations': _normalizeVariations(record['variations']),
  };
}

List<Map<String, Object?>> _normalizeKeyExpressions(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final expression = _clean(item['expression']);
    final meaning = _clean(item['meaning']);
    if (expression.isEmpty || meaning.isEmpty) continue;
    result.add(<String, Object?>{
      'expression': expression,
      'meaning': meaning,
      'note': _nullable(item['note']),
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeSimilarExamples(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final sentence = _clean(item['sentence']);
    final translation = _clean(item['translation']);
    if (sentence.isEmpty || translation.isEmpty) continue;
    result.add(<String, Object?>{
      'sentence': sentence,
      'translation': translation,
      'focus': _nullable(item['focus']),
    });
  }
  return result;
}

List<Map<String, Object?>> _normalizeVariations(Object? value) {
  final result = <Map<String, Object?>>[];
  for (final item in _maps(value)) {
    final sentence = _clean(item['sentence']);
    if (sentence.isEmpty) continue;
    result.add(<String, Object?>{
      'sentence': sentence,
      'translation': _nullable(item['translation']),
    });
  }
  return result;
}

List<String> _normalizeStrings(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value) {
    final text = _clean(item);
    if (text.isNotEmpty) result.add(text);
  }
  return result;
}

/// 把值读成对象列表；非 `Map` 条目直接跳过。
Iterable<Map<String, Object?>> _maps(Object? value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, Object?>();
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

String _clean(Object? value) => value is String ? value.trim() : '';

String? _nullable(Object? value) {
  final text = _clean(value);
  return text.isEmpty ? null : text;
}

/// 解析 `*_json` 列；损坏时返回 `null`，由归一化补默认值。
Object? _decodeColumn(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) return raw;
  if (raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
