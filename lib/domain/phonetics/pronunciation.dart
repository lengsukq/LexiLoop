/// 词条发音（`pronunciations_json`）的解析与选取。
///
/// 对应旧版 `modules/phonetics/selection.ts` 里的 `parsePronunciations` /
/// `displayPhonetic` / `selectPronunciation`。
///
/// **为什么从 selection.ts 里拆出来**：这三段逻辑与「出题」无关，
/// 只回答「这个口音下这个词怎么念」；放在一起会让出题规则的文件
/// 混入 JSON 解析。旧版还有一处历史包袱——早期数据里存在
/// `GENERAL` 口音，旧版把它当作 `US` 处理（不暴露第三种口音），
/// 这里保留同一兼容行为。
library;

import 'dart:convert';

import 'package:lexiloop/domain/enums.dart';

/// 词条的一条发音。
class PhoneticPronunciation {
  /// 以各字段构造。
  const new({required this.accent, required this.phonetic});

  /// 口音。
  final Accent accent;

  /// 音标原文。
  final String phonetic;
}

/// 解析 `pronunciations_json`。
///
/// 结构不符或不是数组时返回空列表（与旧版 `catch { return [] }` 等效，
/// 但这里不吞异常——`jsonDecode` 的 `FormatException` 被显式接住）。
/// 旧数据里的 `GENERAL` 口音归入 [Accent.us]。
List<PhoneticPronunciation> parsePronunciationsJson(String? raw) {
  if (raw == null || raw.isEmpty) return const <PhoneticPronunciation>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const <PhoneticPronunciation>[];
  }
  if (decoded is! List) return const <PhoneticPronunciation>[];

  final result = <PhoneticPronunciation>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final phonetic = item['phonetic'];
    if (phonetic is! String || phonetic.trim().isEmpty) continue;
    result.add(
      PhoneticPronunciation(
        accent: item['accent'] == Accent.uk.wire ? Accent.uk : Accent.us,
        phonetic: phonetic.trim(),
      ),
    );
  }
  return result;
}

/// 目标口音的展示音标（已补斜杠）；没有该口音时返回 `null`。
///
/// 不做「退而求其次用另一口音」的回退：音标训练练的就是口音本身，
/// 拿英音冒充美音会让用户学错。
String? selectPronunciation(
  List<PhoneticPronunciation> pronunciations,
  Accent accent,
) {
  for (final item in pronunciations) {
    if (item.accent != accent) continue;
    final display = displayPhonetic(item.phonetic);
    if (display.isNotEmpty) return display;
  }
  return null;
}

/// 展示格式：补上斜杠（旧版 `displayPhonetic`）。
///
/// 已经是 `/.../` 或 `[...]` 的原样返回；空白压缩为单个空格。
String displayPhonetic(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '';
  final wrapped =
      (normalized.startsWith('/') && normalized.endsWith('/')) ||
      (normalized.startsWith('[') && normalized.endsWith(']'));
  return wrapped ? normalized : '/$normalized/';
}
