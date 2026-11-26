/// 多来源内容的合并核心。
///
/// 对应旧版 `modules/dictionary/merge.ts` 的 `mergeDictionaryContent`。
///
/// **为什么放在 `lib/data/` 而不是 `lib/services/dictionary/`**：有道 provider
/// 需要在返回前把两个端点的结果合并择优（旧版在 provider 里直接调用
/// `mergeDictionaryContent`）。若合并核心只存在于 services 层，
/// `lib/data` 就得反向依赖 `lib/services`。这里放纯数据合并，
/// services 层再包一层 `DictionaryContent` 视图与状态判定。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';

/// 合并任意多个来源的字段映射。
///
/// 规则（照旧版）：
/// - 数组字段做并集，按 [arrayItemKey] 去重，先出现的优先；
/// - 对象字段的标量取第一个非空，内部数组做并集；
/// - 释义最后按 [definitionDuplicateThreshold] 的字符集相似度二次去重，
///   同组重复时保留文本更长（更详细）的一条。
Map<String, Object?> mergeContentFields(List<Map<String, Object?>?> contents) {
  final result = <String, Object?>{
    for (final field in contentArrayFields) field: <Object?>[],
    for (final field in contentObjectFields)
      field: Map<String, Object?>.from(emptyDictionaryContent().record(field)),
  };
  final seen = <String, Set<String>>{
    for (final field in contentArrayFields) field: <String>{},
  };
  for (final raw in contents) {
    if (raw == null) continue;
    final content = normalizeDictionaryContent(raw);
    for (final field in contentArrayFields) {
      _appendArray(result, seen, field, content);
    }
    for (final field in contentObjectFields) {
      result[field] = mergeObjectField(
        field,
        result[field],
        content.fields[field],
      );
    }
  }
  result['definitions'] = deduplicateSimilarDefinitions(
    result['definitions']! as List<Object?>,
  );
  return result;
}

/// 合并一个对象型字段（`summary` / `learning` / `sentenceAnalysis`）。
///
/// 标量取第一个非空；`learning.commonMistakes` 与 `sentenceAnalysis` 的四个
/// 数组按各自的身份键做并集。
Map<String, Object?> mergeObjectField(
  String field,
  Object? existing,
  Object? incoming,
) {
  final left = existing is Map
      ? existing.cast<String, Object?>()
      : <String, Object?>{};
  final right = incoming is Map
      ? incoming.cast<String, Object?>()
      : <String, Object?>{};
  final result = <String, Object?>{};
  for (final key in <String>{...left.keys, ...right.keys}) {
    final leftValue = left[key];
    final rightValue = right[key];
    if (leftValue is List || rightValue is List) {
      result[key] = _unionLists(
        leftValue is List ? leftValue : const <Object?>[],
        rightValue is List ? rightValue : const <Object?>[],
        _listKeyOf(field, key),
      );
      continue;
    }
    result[key] = leftValue ?? rightValue;
  }
  return result;
}

/// 释义的二次去重（同语言同词性内按字符集相似度）。
List<Object?> deduplicateSimilarDefinitions(List<Object?> definitions) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final item in definitions) {
    if (item is! Map) continue;
    final record = item.cast<String, Object?>();
    final key = '${record['language']}|${record['partOfSpeech'] ?? ''}';
    groups.putIfAbsent(key, () => <Map<String, Object?>>[]).add(record);
  }
  final result = <Object?>[];
  for (final group in groups.values) {
    result.addAll(_deduplicateGroup(group));
  }
  return result;
}

/// 两个文本的字符集 Jaccard 相似度（忽略空白与标点）。
double textSimilarity(String left, String right) {
  final a = _significantChars(left);
  final b = _significantChars(right);
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var intersection = 0;
  for (final character in a) {
    if (b.contains(character)) intersection += 1;
  }
  return intersection / (a.length + b.length - intersection);
}

List<Map<String, Object?>> _deduplicateGroup(List<Map<String, Object?>> group) {
  final kept = <Map<String, Object?>>[];
  for (final item in group) {
    if (isUserProtectedItem('definitions', item)) {
      kept.add(item);
      continue;
    }
    final index = kept.indexWhere(
      (candidate) =>
          !isUserProtectedItem('definitions', candidate) &&
          textSimilarity('${candidate['text']}', '${item['text']}') >=
              definitionDuplicateThreshold,
    );
    if (index < 0) {
      kept.add(item);
      continue;
    }
    if ('${item['text']}'.length > '${kept[index]['text']}'.length) {
      kept[index] = item;
    }
  }
  return kept;
}

void _appendArray(
  Map<String, Object?> result,
  Map<String, Set<String>> seen,
  String field,
  DictionaryContent content,
) {
  final target = result[field]! as List<Object?>;
  final keys = seen[field]!;
  if (field == 'tags') {
    for (final tag in content.strings(field)) {
      if (keys.add(tag)) target.add(tag);
    }
    return;
  }
  for (final item in content.records(field)) {
    if (keys.add(arrayItemKey(field, item))) target.add(item);
  }
}

List<Object?> _unionLists(Object? left, Object? right, _ItemKey key) {
  final result = <Object?>[];
  final seen = <String>{};
  for (final source in <Object?>[left, right]) {
    if (source is! List) continue;
    for (final item in source) {
      if (!seen.add(key(item))) continue;
      result.add(item);
    }
  }
  return result;
}

typedef _ItemKey = String Function(Object? item);

_ItemKey _listKeyOf(String field, String key) {
  if (field == 'sentenceAnalysis') {
    if (key == 'keyExpressions') {
      return (item) => _lowerOf(item, 'expression');
    }
    if (key == 'similarExamples' || key == 'variations') {
      return (item) => _lowerOf(item, 'sentence');
    }
  }
  return (item) => '$item';
}

String _lowerOf(Object? item, String key) {
  if (item is! Map) return '$item';
  final value = item[key];
  return value is String ? value.toLowerCase() : '$value';
}

Set<String> _significantChars(String value) {
  final result = <String>{};
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (_punctuationPattern.hasMatch(character)) continue;
    result.add(character.toLowerCase());
  }
  return result;
}

final RegExp _punctuationPattern = RegExp(r'[\s\p{P}]', unicode: true);
