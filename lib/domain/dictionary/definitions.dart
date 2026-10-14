/// 释义（`definitions_json`）的解析与取值。
///
/// 对应旧版 `modules/dictionary/content.ts` 中与判题相关的部分。
/// 旧版把「取目标语言释义文本」的逻辑在 6 个模块里各写了一遍，
/// 这里是唯一实现。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';

/// 一条释义。
class DefinitionValue {
  /// 以各字段构造。
  const new({
    required this.language,
    required this.text,
    this.partOfSpeech,
    this.source,
    this.isUserEdited = false,
  });

  /// 释义所用语言代码。
  final String language;

  /// 释义文本。
  final String text;

  /// 词性。
  final String? partOfSpeech;

  /// 数据来源标识。
  final String? source;

  /// 是否被用户手工编辑过。
  final bool isUserEdited;
}

/// 解析 `definitions_json`。
///
/// 解析失败或结构不符时返回空列表，并**过滤掉空文本**——
/// 空释义会让选择题没有任何选项，必须在源头剔除。
List<DefinitionValue> parseDefinitionsJson(String? raw) {
  if (raw == null || raw.isEmpty) return const <DefinitionValue>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const <DefinitionValue>[];
  }
  if (decoded is! List) return const <DefinitionValue>[];

  final result = <DefinitionValue>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final text = item['text'];
    if (text is! String || text.trim().isEmpty) continue;
    final language = item['language'];
    final partOfSpeech = item['partOfSpeech'];
    final source = item['source'];
    result.add(
      DefinitionValue(
        language: language is String ? language : '',
        text: text,
        partOfSpeech: partOfSpeech is String ? partOfSpeech : null,
        source: source is String ? source : null,
        isUserEdited: item['isUserEdited'] == true,
      ),
    );
  }
  return result;
}

/// 目标语言释义优先，没有则回退到全部释义。
List<DefinitionValue> targetDefinitions(
  List<DefinitionValue> definitions,
  String targetLanguage,
) {
  final target = definitions
      .where((item) => item.language == targetLanguage)
      .toList(growable: false);
  return target.isEmpty ? definitions : target;
}

/// 目标语言释义文本（用 [definitionSeparator] 连接），回退到全部释义。
String targetDefinitionTexts(
  List<DefinitionValue> definitions,
  String targetLanguage, {
  String separator = definitionSeparator,
}) => targetDefinitions(definitions, targetLanguage)
    .map((item) => item.text.trim())
    .where((text) => text.isNotEmpty)
    .join(separator);

/// 首选释义文本：目标语言第一条，否则第一条任意释义；无则 `null`。
String? preferredDefinitionText(
  List<DefinitionValue> definitions,
  String targetLanguage,
) {
  for (final item in definitions) {
    if (item.language == targetLanguage) return item.text;
  }
  return definitions.isEmpty ? null : definitions.first.text;
}
