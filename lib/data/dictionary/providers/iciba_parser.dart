/// 爱词霸页面 → 词条字段。
///
/// 对应旧版 `modules/dictionary/providers/iciba-parser.ts`。
library;

import 'dart:convert';

import 'package:lexiloop/data/dictionary/providers/iciba_fields.dart';

/// 从 `__NEXT_DATA__` 里取出 `wordInfo`。
///
/// 取不到（页面改版、被反爬页面替换、JSON 损坏）时返回 `null`，
/// 由调用方判为「无法解析」而不是抛异常——页面结构变化是常态。
Map<String, Object?>? extractIcibaWordInfo(String html) {
  final match = RegExp(
    '<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
    dotAll: true,
  ).firstMatch(html);
  final raw = match?.group(1);
  if (raw == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final props = decoded['props'];
  if (props is! Map) return null;
  final pageProps = props['pageProps'];
  if (pageProps is! Map) return null;
  final state = pageProps['initialReduxState'];
  if (state is! Map) return null;
  final word = state['word'];
  if (word is! Map) return null;
  final info = word['wordInfo'];
  if (info is! Map) return null;
  return info.cast<String, Object?>();
}

/// 页面是否解析出了任何可用字段。
bool hasAnyIcibaContent(Map<String, Object?> fields) {
  for (final field in <String>[
    'definitions',
    'pronunciations',
    'forms',
    'examples',
    'phrases',
    'synonyms',
    'wordFamily',
    'roots',
    'confusedWords',
    'tags',
  ]) {
    final value = fields[field];
    if (value is List && value.isNotEmpty) return true;
  }
  final summary = fields['summary'];
  if (summary is Map) {
    final short = summary['shortDefinition'];
    if (short is String && short.trim().isNotEmpty) return true;
    if (summary['frequency'] != null) return true;
  }
  return false;
}

/// 解析爱词霸页面。
///
/// 返回逻辑字段名 → 值的原始映射；无任何可用内容时返回 `null`。
Map<String, Object?>? parseIcibaHtml(
  String html, {
  required String targetLanguage,
}) {
  final info = extractIcibaWordInfo(html);
  if (info == null) return null;
  final definitions = parseIcibaDefinitions(info, targetLanguage);
  final baesInfo = info['baesInfo'];
  final hasSymbols = baesInfo is Map && baesInfo['symbols'] is List;
  if (definitions.isEmpty && !hasSymbols) return null;
  final fields = <String, Object?>{
    'definitions': definitions,
    'pronunciations': parseIcibaPhonetics(info),
    'forms': parseIcibaForms(info),
    'examples': parseIcibaExamples(info),
    'phrases': parseIcibaPhrases(info),
    'synonyms': parseIcibaSynonyms(info),
    'wordFamily': const <Map<String, Object?>>[],
    'roots': parseIcibaRoots(info),
    'confusedWords': parseIcibaConfusedWords(info),
    'summary': parseIcibaSummary(info),
    'tags': parseIcibaTags(info),
  };
  return hasAnyIcibaContent(fields) ? fields : null;
}
