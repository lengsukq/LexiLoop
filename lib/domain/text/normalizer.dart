/// 词条文本归一化。
///
/// 对应旧版 `modules/imports/normalizer.ts`。归一化结果是
/// `words.normalized_term` 的唯一来源，也是判题时的比对基准——
/// 两侧必须走**同一个**函数，否则会出现「能导入但判错」的幽灵 bug。
///
/// 本文件必须保持纯 Dart（无 Flutter / IO / 框架依赖）。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 归一化词条文本：NFKC 规范化、压缩空白，并对小写语言族取小写。
///
/// 旧版用 `toLocaleLowerCase`；Dart 的 `toLowerCase()` 无 locale 参数，
/// 对 [lowercaseLanguages] 中的语言两者行为一致（土耳其语 İ 不在集合内）。
String normalizeTerm(String term, String languageCode) {
  final normalized = _compressWhitespace(unorm.nfkc(term));
  return lowercaseLanguages.contains(languageCode)
      ? normalized.toLowerCase()
      : normalized;
}

/// 展示用词条文本。
///
/// 仅对**单词**且属于小写语言族的词条取小写；短语与句子保持原始大小写，
/// 避免破坏专有名词或句子语义。
String displayTerm(String term, String languageCode, LexicalContentType type) {
  if (type != LexicalContentType.word) return term;
  if (!lowercaseLanguages.contains(languageCode)) return term;
  return unorm.nfkc(term).toLowerCase();
}

/// 词条唯一性键：归一化文本 + 源语言 + 目标语言。
///
/// 用 `\u0000` 分隔而不是常见分隔符，避免词条文本本身含分隔符时产生碰撞。
String identityKey(
  String normalizedTerm,
  String sourceLanguage,
  String targetLanguage,
) => '$normalizedTerm\u0000$sourceLanguage\u0000$targetLanguage';

String _compressWhitespace(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');
