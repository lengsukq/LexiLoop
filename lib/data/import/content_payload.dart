/// EasyDict CSV 字段 → `word_contents` JSON 列的组装。
///
/// **为什么列形状在这里而不是服务里**：旧版把每种字段的 JSON 结构散在
/// `imports/commit.ts` 与各 provider 的 mapper 里，同一个字段在两条路径上
/// 形状不一致（例如 `confusedWords` 有的带 `relation` 有的不带）。
/// 集中一处后，「导入写入的形状」只有这一个出处。
///
/// 形状与旧版 `modules/imports/commit.ts` 一致：
/// `definitions` / `examples` / `confusedWords` 是对象数组，
/// `tags` 是纯字符串数组。
library;

import 'dart:convert';

import 'package:lexiloop/data/import/csv_parser.dart';

/// CSV 内容的来源标识，写入每条内容的 `source` 字段。
const String easydictCsvSource = 'easydict-csv';

/// 易混词关系的固定取值。
const String confusedWithRelation = 'CONFUSED_WITH';

/// `word_contents` 中由 CSV 直接提供的列（键为 Drift 字段名）。
///
/// 用 Drift 字段名而非数据库列名做键：服务层构造 `WordContentsCompanion`
/// 时按同一批键取值，两处不会各写一套字符串。
abstract final class ContentColumns {
  /// 释义。
  static const String definitions = 'definitionsJson';

  /// 音标 / 发音。
  static const String pronunciations = 'pronunciationsJson';

  /// 例句。
  static const String examples = 'examplesJson';

  /// 短语。
  static const String phrases = 'phrasesJson';

  /// 同义词。
  static const String synonyms = 'synonymsJson';

  /// 反义词。
  static const String antonyms = 'antonymsJson';

  /// 词族。
  static const String wordFamily = 'wordFamilyJson';

  /// 易混词。
  static const String confusedWords = 'confusedWordsJson';

  /// 词根。
  static const String roots = 'rootsJson';

  /// 词缀。
  static const String affixes = 'affixesJson';

  /// 标签。
  static const String tags = 'tagsJson';
}

/// 把一行解析结果组装为 JSON 列（**只含非空字段**）。
///
/// 只输出非空字段有两个好处：
/// 1. `FILL_MISSING` 只需按「当前列是否为空」决定写不写；
/// 2. 不会用空数组覆盖掉数据源已经补齐的内容。
Map<String, String> contentColumnsFromRow(
  ParsedCsvRow row, {
  required String targetLanguage,
}) {
  final result = <String, String>{};
  final definition = row.definitionText;
  if (definition != null && definition.isNotEmpty) {
    result[ContentColumns.definitions] = jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'language': targetLanguage,
        'text': definition,
        'source': easydictCsvSource,
      },
    ]);
  }
  final phonetic = row.phonetic;
  if (phonetic != null && phonetic.isNotEmpty) {
    result[ContentColumns.pronunciations] = jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'text': phonetic,
        'accent': null,
        'source': easydictCsvSource,
      },
    ]);
  }
  _putIfNotEmpty(
    result,
    ContentColumns.examples,
    row.examples.map(
      (item) => <String, Object?>{
        'sentence': item,
        'translation': null,
        'source': easydictCsvSource,
      },
    ),
  );
  _putIfNotEmpty(
    result,
    ContentColumns.phrases,
    row.phrases.map(
      (item) => <String, Object?>{'phrase': item, 'source': easydictCsvSource},
    ),
  );
  _putWords(result, ContentColumns.synonyms, row.synonyms);
  _putWords(result, ContentColumns.antonyms, row.antonyms);
  _putWords(result, ContentColumns.wordFamily, row.wordFamilies);
  _putWords(result, ContentColumns.confusedWords, row.confusedWords);
  _putIfNotEmpty(
    result,
    ContentColumns.roots,
    row.roots.map(
      (item) => <String, Object?>{'root': item, 'source': easydictCsvSource},
    ),
  );
  _putIfNotEmpty(
    result,
    ContentColumns.affixes,
    row.affixes.map(
      (item) => <String, Object?>{'affix': item, 'source': easydictCsvSource},
    ),
  );
  if (row.tags.isNotEmpty) {
    result[ContentColumns.tags] = jsonEncode(row.tags);
  }
  return result;
}

/// 该列在既有内容中是否算「缺失」。
///
/// 判定为缺失的两种情况：JSON 不是非空数组；或（仅释义列）数组里没有
/// 目标语言的条目。后者对应旧版「已有英文释义但没有中文释义」的场景——
/// 此时 `FILL_MISSING` 应当补上中文，而不是因为数组非空就跳过。
bool isContentColumnMissing(
  String column,
  String? currentJson, {
  required String targetLanguage,
}) {
  final decoded = _decodeList(currentJson);
  if (decoded.isEmpty) return true;
  if (column != ContentColumns.definitions) return false;
  return !decoded.any((item) {
    if (item is! Map) return false;
    final text = item['text'];
    return item['language'] == targetLanguage &&
        text is String &&
        text.isNotEmpty;
  });
}

void _putIfNotEmpty(
  Map<String, String> target,
  String column,
  Iterable<Map<String, Object?>> items,
) {
  final list = items.toList(growable: false);
  if (list.isEmpty) return;
  target[column] = jsonEncode(list);
}

void _putWords(Map<String, String> target, String column, List<String> words) {
  if (words.isEmpty) return;
  target[column] = jsonEncode(
    words
        .map(
          (word) => <String, Object?>{
            'word': word,
            if (column == ContentColumns.confusedWords)
              'relation': confusedWithRelation,
            'source': easydictCsvSource,
          },
        )
        .toList(growable: false),
  );
}

List<Object?> _decodeList(String? json) {
  if (json == null || json.isEmpty) return const <Object?>[];
  try {
    final decoded = jsonDecode(json);
    return decoded is List ? decoded : const <Object?>[];
  } on FormatException {
    // 坏 JSON 视为「缺失」：宁可让 FILL_MISSING 覆盖它，也不要保留脏数据。
    return const <Object?>[];
  }
}
