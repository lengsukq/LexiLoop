/// 有道页面 → 词条字段。
///
/// 对应旧版 `modules/dictionary/providers/youdao-parser.ts`。
library;

import 'package:lexiloop/data/dictionary/html_text.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_fields.dart';
import 'package:lexiloop/domain/enums.dart';

/// 解析有道词典页面。
///
/// 返回逻辑字段名 → 值的原始映射（由调用方归一化）；页面无任何可用内容时
/// 返回 `null`。`WORD` 与 `PHRASE`/`SENTENCE` 的字段集合不同：
/// 音标、词形、同根词只对单词有意义，短语与句子则依赖「有道翻译」直译块。
Map<String, Object?>? parseYoudaoHtml(
  String html, {
  required String term,
  required LexicalContentType contentType,
  required String targetLanguage,
}) {
  final lines = extractTextLines(html);
  if (lines.isEmpty) return null;
  final isWord = contentType == LexicalContentType.word;
  final translation = parseYoudaoTranslation(lines, term, targetLanguage);
  final definitions = <Map<String, Object?>>[
    ...parseYoudaoDefinitions(lines, targetLanguage),
    if (isWord) ...parseYoudaoEnDefinitions(html),
  ];
  final examples = parseYoudaoExamples(lines, term);
  final phrases = _mergePhrases(
    parseYoudaoPhrases(lines),
    parseYoudaoPhrasesFromHtml(html),
  );
  final content = <String, Object?>{
    'pronunciations': isWord
        ? parseYoudaoPhonetics(lines, term, html)
        : const <Map<String, Object?>>[],
    'definitions': definitions,
    'forms': isWord
        ? parseYoudaoWordForms(lines)
        : const <Map<String, Object?>>[],
    'examples': examples,
    'phrases': phrases,
    'synonyms': isWord
        ? parseYoudaoSynonymsFromHtml(html)
        : const <Map<String, Object?>>[],
    'wordFamily': isWord
        ? parseYoudaoWordFamilyFromHtml(html)
        : const <Map<String, Object?>>[],
    'tags': parseYoudaoTags(lines),
  };
  if (translation != null) {
    return _applyTranslation(
      content: content,
      translation: translation,
      term: term,
      contentType: contentType,
      targetLanguage: targetLanguage,
      definitions: definitions,
      examples: examples,
      phrases: phrases,
    );
  }
  if (contentType == LexicalContentType.phrase && definitions.isEmpty) {
    final phraseDefinition = parseYoudaoPhraseDefinition(
      lines,
      term,
      targetLanguage,
    );
    if (phraseDefinition != null) {
      content['definitions'] = <Map<String, Object?>>[
        _translationDefinition(phraseDefinition, targetLanguage),
      ];
    }
  }
  return content;
}

/// 页面是否解析出了任何可用字段。
///
/// 全空的字段集合必须被当作 `EMPTY` 而不是 `SUCCESS`，
/// 否则 `provider_attempts` 会记录一堆「成功但什么都没有」的假阳性。
bool hasAnyYoudaoContent(Map<String, Object?> fields) {
  for (final field in <String>[
    'definitions',
    'pronunciations',
    'forms',
    'examples',
    'phrases',
    'synonyms',
    'antonyms',
    'wordFamily',
    'roots',
    'affixes',
  ]) {
    final value = fields[field];
    if (value is List && value.isNotEmpty) return true;
  }
  final summary = fields['summary'];
  if (summary is Map) {
    for (final key in <String>['translation', 'shortDefinition']) {
      final value = summary[key];
      if (value is String && value.trim().isNotEmpty) return true;
    }
  }
  return false;
}

Map<String, Object?> _applyTranslation({
  required Map<String, Object?> content,
  required Map<String, Object?> translation,
  required String term,
  required LexicalContentType contentType,
  required String targetLanguage,
  required List<Map<String, Object?>> definitions,
  required List<Map<String, Object?>> examples,
  required List<Map<String, Object?>> phrases,
}) {
  final text = translation['translation'];
  final source = translation['source'];
  content['summary'] = <String, Object?>{
    'shortDefinition': null,
    'translation': text,
    'cefrLevel': null,
    'frequency': null,
  };
  if (contentType == LexicalContentType.word) return content;
  content['definitions'] = <Map<String, Object?>>[
    _translationDefinition(translation, targetLanguage),
    ...definitions,
  ];
  content['examples'] = <Map<String, Object?>>[
    <String, Object?>{
      'sentence': term,
      'translation': text,
      'source': source,
      'isUserAdded': false,
    },
    ...examples,
  ];
  if (contentType == LexicalContentType.phrase) {
    content['phrases'] = <Map<String, Object?>>[
      <String, Object?>{'phrase': term, 'translation': text, 'source': source},
      ...phrases,
    ];
  }
  return content;
}

Map<String, Object?> _translationDefinition(
  Map<String, Object?> translation,
  String targetLanguage,
) => <String, Object?>{
  'language': targetLanguage,
  'partOfSpeech': null,
  'text': translation['text'] ?? translation['translation'],
  'source': translation['source'],
  'isUserEdited': false,
};

List<Map<String, Object?>> _mergePhrases(
  List<Map<String, Object?>> first,
  List<Map<String, Object?>> second,
) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  final seen = <String>{
    for (final item in first) '${item['phrase']}'.toLowerCase(),
  };
  final merged = <Map<String, Object?>>[...first];
  for (final item in second) {
    if (seen.add('${item['phrase']}'.toLowerCase())) merged.add(item);
  }
  return merged;
}
