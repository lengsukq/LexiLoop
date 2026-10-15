/// 爱词霸（金山词霸）词条字段解析。
///
/// 对应旧版 `modules/dictionary/providers/iciba-fields.ts`。
///
/// 爱词霸的新版页面是 Next.js 应用，词条数据整体塞在
/// `<script id="__NEXT_DATA__">` 的 `wordInfo` 里，因此这里全部是
/// **结构化字段映射**而不是 HTML 正则——比有道稳定得多。
library;

import 'package:lexiloop/data/dictionary/html_text.dart';

/// 词典字段的来源标识。
const String icibaSource = 'iciba';

/// 英英释义的来源标识。
const String icibaEnSource = 'iciba:en-definition';

/// 柯林斯释义的来源标识。
const String icibaCollinsSource = 'iciba:collins';

/// 例句的来源标识。
const String icibaExampleSource = 'iciba:example';

/// 短语的来源标识。
const String icibaPhraseSource = 'iciba:phrase';

/// 详细释义的来源标识。
const String icibaBidecSource = 'iciba:bidec';

/// 词性缩写归一化（`noun` → `n`）。
String? normalizeIcibaPos(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'\.$'), '').toLowerCase();
  if (trimmed.isEmpty) return null;
  const aliases = <String, String>{
    'noun': 'n',
    'verb': 'v',
    'vt': 'v',
    'vi': 'v',
    'adjective': 'adj',
    'adverb': 'adv',
  };
  return aliases[trimmed] ?? trimmed;
}

/// 解析释义（简明 + 详细 + 英英 + 柯林斯）。
List<Map<String, Object?>> parseIcibaDefinitions(
  Map<String, Object?> info,
  String targetLanguage,
) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  _appendConcise(info, targetLanguage, result, seen);
  _appendBidec(info, targetLanguage, result, seen);
  _appendEnMean(info, result, seen);
  _appendCollins(info, targetLanguage, result, seen);
  return result;
}

void _appendConcise(
  Map<String, Object?> info,
  String targetLanguage,
  List<Map<String, Object?>> result,
  Set<String> seen,
) {
  final baesInfo = _map(info['baesInfo']);
  for (final symbol in _list(baesInfo['symbols'])) {
    final parts = _list(_map(symbol)['parts']);
    for (final part in parts) {
      final record = _map(part);
      final pos = normalizeIcibaPos(_string(record['part']));
      for (final raw in _list(record['means'])) {
        _pushDefinition(
          result,
          seen,
          language: targetLanguage,
          partOfSpeech: pos,
          text: _clean(raw),
          source: icibaSource,
        );
      }
    }
  }
}

void _appendBidec(
  Map<String, Object?> info,
  String targetLanguage,
  List<Map<String, Object?>> result,
  Set<String> seen,
) {
  final bidec = _map(info['bidec']);
  for (final part in _list(bidec['parts'])) {
    final record = _map(part);
    final rawPos = _string(record['part_name']).trim();
    final pos = normalizeIcibaPos(rawPos);
    for (final mean in _list(record['means'])) {
      final text = _clean(_map(mean)['word_mean'])
          .replaceAll(RegExp('</seg>', caseSensitive: false), '')
          .trim();
      if (pos == null &&
          RegExp(r'^_no_$', caseSensitive: false).hasMatch(rawPos)) {
        continue;
      }
      _pushDefinition(
        result,
        seen,
        language: targetLanguage,
        partOfSpeech: pos,
        text: text,
        source: icibaBidecSource,
      );
    }
  }
}

void _appendEnMean(
  Map<String, Object?> info,
  List<Map<String, Object?>> result,
  Set<String> seen,
) {
  for (final group in _list(info['ee_mean'])) {
    final record = _map(group);
    final pos = normalizeIcibaPos(_string(record['part_name']));
    for (final mean in _list(record['means'])) {
      final text = _clean(_map(mean)['word_mean'])
          .replaceAll(RegExp(r'^\d+\.\s*'), '');
      _pushDefinition(
        result,
        seen,
        language: 'en',
        partOfSpeech: pos,
        text: text,
        source: icibaEnSource,
      );
    }
  }
}

void _appendCollins(
  Map<String, Object?> info,
  String targetLanguage,
  List<Map<String, Object?>> result,
  Set<String> seen,
) {
  for (final block in _list(info['collins'])) {
    for (final entry in _list(_map(block)['entry'])) {
      final record = _map(entry);
      final posp = _string(record['posp']).isEmpty
          ? null
          : normalizeIcibaPos(
              _string(record['posp']).replaceAll(RegExp(r'-.*$'), ''),
            );
      _pushDefinition(
        result,
        seen,
        language: 'en',
        partOfSpeech: posp,
        text: _clean(record['def']),
        source: icibaCollinsSource,
      );
      _pushDefinition(
        result,
        seen,
        language: targetLanguage,
        partOfSpeech: posp,
        text: _clean(record['tran']),
        source: icibaCollinsSource,
      );
    }
  }
}

void _pushDefinition(
  List<Map<String, Object?>> result,
  Set<String> seen, {
  required String language,
  required String? partOfSpeech,
  required String text,
  required String source,
}) {
  if (text.isEmpty) return;
  if (!seen.add('$language|${partOfSpeech ?? ''}|$text')) return;
  result.add(<String, Object?>{
    'language': language,
    'partOfSpeech': partOfSpeech,
    'text': text,
    'source': source,
    'isUserEdited': false,
  });
}

/// 解析英/美音标与音频。
List<Map<String, Object?>> parseIcibaPhonetics(Map<String, Object?> info) {
  final baesInfo = _map(info['baesInfo']);
  final symbols = _list(baesInfo['symbols']);
  if (symbols.isEmpty) return const <Map<String, Object?>>[];
  final symbol = _map(symbols.first);
  final result = <Map<String, Object?>>[];
  final uk = _string(symbol['ph_en']).trim();
  final us = _string(symbol['ph_am']).trim();
  if (uk.isNotEmpty) {
    result.add(_pronunciation('UK', uk, _string(symbol['ph_en_mp3']).trim()));
  }
  if (us.isNotEmpty) {
    result.add(_pronunciation('US', us, _string(symbol['ph_am_mp3']).trim()));
  }
  return result;
}

Map<String, Object?> _pronunciation(
  String accent,
  String phonetic,
  String audio,
) => <String, Object?>{
  'accent': accent,
  'phonetic': phonetic,
  'audioUrl': audio.isEmpty ? null : audio,
  'source': icibaSource,
  'isSynthetic': false,
};

/// 词形变化。
List<Map<String, Object?>> parseIcibaForms(Map<String, Object?> info) {
  final exchange = _map(_map(info['baesInfo'])['exchange']);
  const mapping = <String, String>{
    'word_pl': 'PLURAL',
    'word_third': 'THIRD_PERSON',
    'word_past': 'PAST',
    'word_done': 'PAST_PARTICIPLE',
    'word_ing': 'PRESENT_PARTICIPLE',
    'word_er': 'COMPARATIVE',
    'word_est': 'SUPERLATIVE',
    'word_adj': 'OTHER',
  };
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final entry in mapping.entries) {
    for (final raw in _list(exchange[entry.key])) {
      final value = _clean(raw);
      if (value.isEmpty) continue;
      if (!seen.add('${entry.value}|${value.toLowerCase()}')) continue;
      result.add(<String, Object?>{
        'type': entry.value,
        'value': value,
        'source': icibaSource,
      });
    }
  }
  return result;
}

/// 例句（简明 / 详细 / 英英 / 柯林斯 / 短语例句，最多 20 条）。
List<Map<String, Object?>> parseIcibaExamples(Map<String, Object?> info) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  _appendExamples(
    result,
    seen,
    _list(_map(info['bidec'])['parts']),
    nested: 'means',
    sentenceKey: 'en',
    translationKey: 'cn',
  );
  _appendExamples(
    result,
    seen,
    _list(info['ee_mean']),
    nested: 'means',
    sentenceKey: 'sentence',
    translationKey: null,
  );
  for (final block in _list(info['new_sentence'])) {
    _appendSentencePairs(
      result,
      seen,
      _list(_map(block)['sentences']),
      'en',
      'cn',
    );
  }
  for (final block in _list(info['collins'])) {
    for (final entry in _list(_map(block)['entry'])) {
      _appendSentencePairs(
        result,
        seen,
        _list(_map(entry)['example']),
        'ex',
        'tran',
      );
    }
  }
  for (final phrase in _list(info['phrase'])) {
    for (final jx in _list(_map(phrase)['jx'])) {
      _appendSentencePairs(
        result,
        seen,
        _list(_map(jx)['lj']),
        'lj_ly',
        'lj_ls',
      );
    }
  }
  return result.length > _maxIcibaExamples
      ? result.sublist(0, _maxIcibaExamples)
      : result;
}

/// 例句数量上限——爱词霸会返回上百条，全部落库没有意义。
const int _maxIcibaExamples = 20;

void _appendExamples(
  List<Map<String, Object?>> result,
  Set<String> seen,
  List<Object?> groups, {
  required String nested,
  required String sentenceKey,
  required String? translationKey,
}) {
  for (final group in groups) {
    for (final mean in _list(_map(group)[nested])) {
      _appendSentencePairs(
        result,
        seen,
        _list(_map(mean)['sentences']),
        sentenceKey,
        translationKey,
      );
    }
  }
}

void _appendSentencePairs(
  List<Map<String, Object?>> result,
  Set<String> seen,
  List<Object?> rows,
  String sentenceKey,
  String? translationKey,
) {
  for (final row in rows) {
    final record = _map(row);
    final sentence = _clean(record[sentenceKey]);
    if (sentence.length < _minIcibaExampleChars) continue;
    final translation = translationKey == null
        ? ''
        : _clean(record[translationKey]);
    if (!seen.add(sentence.toLowerCase())) continue;
    result.add(<String, Object?>{
      'sentence': sentence,
      'translation': translation.isEmpty ? null : translation,
      'source': icibaExampleSource,
      'isUserAdded': false,
    });
  }
}

/// 例句最短字符数。
const int _minIcibaExampleChars = 5;

/// 短语。
List<Map<String, Object?>> parseIcibaPhrases(Map<String, Object?> info) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final raw in _list(info['phrase'])) {
    final record = _map(raw);
    final phrase = _clean(record['cizu_name']);
    if (phrase.length < 2 || phrase.length > 80) continue;
    if (!seen.add(phrase.toLowerCase())) continue;
    final translations = _list(record['jx']);
    final translation = translations.isEmpty
        ? ''
        : _clean(_map(translations.first)['jx_cn_mean']);
    result.add(<String, Object?>{
      'phrase': phrase,
      'translation': translation.isEmpty ? null : translation,
      'source': icibaPhraseSource,
    });
  }
  return result;
}

/// 同义词。
List<Map<String, Object?>> parseIcibaSynonyms(Map<String, Object?> info) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  for (final group in _list(info['synonym'])) {
    final record = _map(group);
    final pos = normalizeIcibaPos(_string(record['part_name']));
    for (final mean in _list(record['means'])) {
      for (final raw in _list(_map(mean)['cis'])) {
        final word = _clean(raw);
        if (!_isIcibaWord(word)) continue;
        if (!seen.add(word.toLowerCase())) continue;
        result.add(<String, Object?>{
          'word': word,
          'translation': null,
          'partOfSpeech': pos,
          'relation': 'SYNONYM',
          'source': icibaSource,
          'difference': null,
        });
      }
    }
  }
  return result;
}

bool _isIcibaWord(String word) {
  if (word.length < 2 || word.length > 40) return false;
  return RegExp(r"^[a-zA-Z][a-zA-Z\s'-]*$").hasMatch(word);
}

/// 词源（爱词霸把它归在「词根」下）。
List<Map<String, Object?>> parseIcibaRoots(Map<String, Object?> info) {
  final result = <Map<String, Object?>>[];
  final wordName = _string(_map(info['baesInfo'])['word_name']);
  for (final raw in _list(info['derivation'])) {
    final text = _clean(_map(raw)['yuyuan_name']);
    if (text.isEmpty) continue;
    result.add(<String, Object?>{
      'root': wordName,
      'meaning': text,
      'origin': null,
      'source': icibaSource,
    });
  }
  return result;
}

/// 易混词（`sameAnalysis`）。
List<Map<String, Object?>> parseIcibaConfusedWords(Map<String, Object?> info) {
  final result = <Map<String, Object?>>[];
  final seen = <String>{};
  final self = _string(_map(info['baesInfo'])['word_name']).toLowerCase();
  for (final raw in _list(info['sameAnalysis'])) {
    final record = _map(raw);
    final words = _string(record['word_list'])
        .split(RegExp('[,，]'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final means = _list(record['means']);
    for (var index = 0; index < words.length; index += 1) {
      final word = words[index];
      if (!RegExp(r"^[a-zA-Z][a-zA-Z\s'-]*$").hasMatch(word)) continue;
      final key = word.toLowerCase();
      if (key == self || !seen.add(key)) continue;
      final difference = index < means.length ? _clean(means[index]) : '';
      result.add(<String, Object?>{
        'word': word,
        'translation': null,
        'partOfSpeech': null,
        'relation': 'CONFUSED',
        'source': icibaSource,
        'difference': difference.isEmpty ? null : difference,
      });
    }
  }
  return result;
}

/// 摘要（首条释义作为短释义，词频映射为频度档位）。
Map<String, Object?> parseIcibaSummary(Map<String, Object?> info) {
  final baesInfo = _map(info['baesInfo']);
  final frequency = _frequencyOf(baesInfo['frequence']);
  final shortDefinition = _firstMean(baesInfo);
  return <String, Object?>{
    'shortDefinition': shortDefinition,
    'translation': null,
    'cefrLevel': null,
    'frequency': frequency,
  };
}

String? _firstMean(Map<String, Object?> baesInfo) {
  final symbols = _list(baesInfo['symbols']);
  if (symbols.isEmpty) return null;
  final parts = _list(_map(symbols.first)['parts']);
  if (parts.isEmpty) return null;
  final means = _list(_map(parts.first)['means']);
  if (means.isEmpty) return null;
  final text = _clean(means.first);
  if (text.isEmpty) return null;
  return text.length > _maxShortDefinitionChars
      ? text.substring(0, _maxShortDefinitionChars)
      : text;
}

/// 短释义字符上限。
const int _maxShortDefinitionChars = 120;

String? _frequencyOf(Object? raw) {
  if (raw is! num) return null;
  final value = raw.toDouble();
  if (value >= _frequencyVeryCommon) return 'VERY_COMMON';
  if (value >= _frequencyCommon) return 'COMMON';
  if (value >= _frequencyNormal) return 'NORMAL';
  if (value > 0) return 'RARE';
  return null;
}

const double _frequencyVeryCommon = 5;
const double _frequencyCommon = 4;
const double _frequencyNormal = 3;

/// 考试标签（爱词霸用数字编码）。
List<String> parseIcibaTags(Map<String, Object?> info) {
  const tagMap = <int, String>{1: 'CET4', 2: 'CET6', 3: '考研', 4: '初中', 5: '高中'};
  final tags = <String>{};
  for (final raw in _list(_map(info['baesInfo'])['word_tag'])) {
    if (raw is! num) continue;
    final label = tagMap[raw.round()];
    if (label != null) tags.add(label);
  }
  return tags.toList(growable: false);
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String _string(Object? value) => value is String ? value : '';

String _clean(Object? value) =>
    decodeHtmlEntities(stripHtmlTags(_string(value))).trim();
