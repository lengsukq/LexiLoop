/// `word_contents` 各 JSON 列的解析原语。
///
/// **为什么要有这个模块**：这些列的形态是「字符串或对象」混合的历史遗留
/// （真实备份里 `synonyms_json` 是对象数组，而早期数据里有纯字符串数组）。
/// 学习会话（`StudyDao`）与词条详情（`WordDetailDao`）都需要同一套容错解析，
/// 各自实现一份会漂移——旧版 `CLEAN_CODE_BASELINE.md` 把「同一逻辑多处实现」
/// 列为最严重的问题类别。
///
/// **真实数据形态**（用 27MB 生产备份逐列核对过）：
/// - `definitions_json`:
///   `[{language, partOfSpeech, text, source, isUserEdited, ...}]`
/// - `pronunciations_json`:
///   `[{accent, phonetic, audioUrl, source, isSynthetic}]`
/// - `examples_json`: `[{sentence, translation, source, isUserAdded, ...}]`
/// - `phrases_json`: `[{phrase, translation, source, example?, kind?}]`
/// - `forms_json`: `[{type, value, source}]`（`type` 形如 `LEMMA`）
/// - `synonyms/antonyms/word_family/confused_words_json`:
///   `[{word, translation, partOfSpeech, relation, source, difference}]`
/// - `roots_json`: `[{root, meaning, origin, source}]`
/// - `affixes_json`: `[{value, meaning, type: PREFIX|SUFFIX, source}]`
/// - `tags_json`: `["ielts", ...]`（纯字符串数组）
/// - `summary_json` / `learning_json` / `sentence_analysis_json`: **对象**，不是数组
library;

import 'dart:convert';

import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 通用文本提取时依次尝试的键。
///
/// 同一份内容在不同 provider 下用了不同的键名（`phrase` / `value` /
/// `sentence` …）。按优先级扫描比给每个列写一个专用解析器更稳，
/// 也不会因为某个 provider 换键名就静默丢内容。
const List<String> textKeys = <String>[
  'text',
  'value',
  'word',
  'sentence',
  'phrase',
  'form',
  'expression',
  'name',
  'label',
  'term',
  'level',
];

/// 解析 JSON；非法内容或空串返回 `null`。
///
/// 只吞 `FormatException`（`jsonDecode` 的契约），其他异常继续上抛——
/// 空 `catch` 会把真实缺陷一起吞掉，这是守卫测试明令禁止的。
Object? decodeJson(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

/// 解析 JSON 数组；非法内容或非数组返回空列表。
List<Object?> decodeJsonList(String? raw) {
  final decoded = decodeJson(raw);
  return decoded is List ? decoded : const <Object?>[];
}

/// 解析 JSON 对象；非法内容或非对象返回空 Map。
Map<Object?, Object?> decodeJsonMap(String? raw) {
  final decoded = decodeJson(raw);
  return decoded is Map ? decoded : const <Object?, Object?>{};
}

/// 取文本：接受字符串、数字，或含 [textKeys] 中任一键的对象。
String textOf(Object? value) {
  if (value is String) return value.trim();
  if (value is num) return value.toString();
  if (value is Map) {
    for (final key in textKeys) {
      final nested = value[key];
      if (nested is String && nested.trim().isNotEmpty) {
        return nested.trim();
      }
    }
  }
  return '';
}

/// 取可空文本；空串归一为 `null`，避免界面出现空行。
String? nullableTextOf(Object? value) {
  final text = textOf(value);
  return text.isEmpty ? null : text;
}

/// 从对象元素里取一个可空文本字段；非对象元素返回 `null`。
String? fieldOf(Object? item, String key) =>
    item is Map ? nullableTextOf(item[key]) : null;

/// 解析文本列表字段；元素可能是字符串、数字或对象。
///
/// 单个字符串也接受（历史数据里 `commonMistakes` 有写成字符串的形态）。
List<String> parseTextList(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? const <String>[] : <String>[text];
  }
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final item in value) {
    final text = textOf(item);
    if (text.isNotEmpty) result.add(text);
  }
  return result;
}

/// 取相关词条元素的词条文本。
///
/// 对象形态优先读 `word` 键；读不到时退回通用文本键，
/// 使 `{term: "apple"}` 这类变体也不至于整条丢失。
String relatedWordOf(Object? item) {
  if (item is Map) {
    final word = textOf(item['word']);
    return word.isNotEmpty ? word : textOf(item);
  }
  return textOf(item);
}

/// 解析发音列表（`pronunciations_json`），跳过无音标的条目。
List<PronunciationView> parsePronunciations(String? raw) {
  final result = <PronunciationView>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final phonetic = textOf(item['phonetic']);
    if (phonetic.isEmpty) continue;
    result.add(
      PronunciationView(
        accent: item['accent'] == Accent.uk.wire ? Accent.uk : Accent.us,
        phonetic: phonetic,
        audioUrl: fieldOf(item, 'audioUrl'),
      ),
    );
  }
  return result;
}

/// 解析例句列表（`examples_json`），跳过句子为空的条目。
List<ExampleView> parseExamples(String? raw) {
  final result = <ExampleView>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final sentence = textOf(item['sentence']);
    if (sentence.isEmpty) continue;
    result.add(
      ExampleView(
        sentence: sentence,
        translation: fieldOf(item, 'translation'),
      ),
    );
  }
  return result;
}

/// `examples_json` 里是否至少有一条带非空句子的例句。
bool hasExampleIn(String? raw) {
  for (final item in decodeJsonList(raw)) {
    if (item is Map && textOf(item['sentence']).isNotEmpty) return true;
  }
  return false;
}

/// 句子类词条的整句翻译（`summary.translation`）。
///
/// 句子常常没有独立释义，含义只在这一个字段里；学习队列的「有可用含义」
/// 判定会用到它（见 `StudyDao` 的候选查询）。
String? summaryTranslationOf(String? raw) {
  final decoded = decodeJsonMap(raw);
  return nullableTextOf(decoded['translation']);
}
