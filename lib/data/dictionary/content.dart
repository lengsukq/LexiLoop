/// 词条内容的数据形态。
///
/// 对应旧版 `modules/dictionary/content.ts` 的 `DictionaryContent`。
///
/// **为什么用 `Map<String, Object?>` 而不是十几个类型化列表**：
/// 这 16 个逻辑字段最终就是 `word_contents` 的 16 个 JSON 列，中间再引入
/// 一层强类型只会让「列名 ↔ 字段名」的映射多写两遍，而合并逻辑真正需要的
/// 只有「数组去重键」与「是否用户产出」两条信息——那两条已由
/// [arrayItemKey] 与 [isUserProtectedItem] 单独具名。
///
/// 每个字段的 JSON 形态与 `lib/data/db/tables/word_tables.dart` 的默认值一致。
library;

import 'dart:convert';

/// 数组型字段（并集去重）。
const List<String> contentArrayFields = <String>[
  'definitions',
  'pronunciations',
  'examples',
  'phrases',
  'forms',
  'synonyms',
  'antonyms',
  'wordFamily',
  'confusedWords',
  'roots',
  'affixes',
  'tags',
];

/// 对象型字段（标量取第一个非空，内部数组取并集）。
const List<String> contentObjectFields = <String>[
  'summary',
  'learning',
  'sentenceAnalysis',
];

/// 全部逻辑字段。
const List<String> contentFields = <String>[
  ...contentArrayFields,
  ...contentObjectFields,
];

/// 逻辑字段名 → `word_contents` 列名。
///
/// 只有一处映射表：备份导出、内容落库、字段完备性判定都读它，
/// 避免旧版那种「列名在三个文件里各写一遍」的漂移。
const Map<String, String> contentColumnNames = <String, String>{
  'definitions': 'definitions_json',
  'pronunciations': 'pronunciations_json',
  'examples': 'examples_json',
  'phrases': 'phrases_json',
  'forms': 'forms_json',
  'synonyms': 'synonyms_json',
  'antonyms': 'antonyms_json',
  'wordFamily': 'word_family_json',
  'confusedWords': 'confused_words_json',
  'roots': 'roots_json',
  'affixes': 'affixes_json',
  'summary': 'summary_json',
  'learning': 'learning_json',
  'sentenceAnalysis': 'sentence_analysis_json',
  'tags': 'tags_json',
};

/// 词条内容：逻辑字段名 → JSON 可序列化的值。
class DictionaryContent {
  /// 以字段映射构造。
  const new(this.fields);

  /// 逻辑字段名 → 值（数组字段为 `List`，对象字段为 `Map`）。
  final Map<String, Object?> fields;

  /// 是否没有任何字段。
  bool get isEmpty => fields.isEmpty;

  /// 取数组字段中的对象条目（非数组或非对象条目被忽略）。
  List<Map<String, Object?>> records(String field) {
    final value = fields[field];
    if (value is! List) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final item in value) {
      if (item is Map) result.add(item.cast<String, Object?>());
    }
    return result;
  }

  /// 取对象字段（非对象时返回空映射）。
  Map<String, Object?> record(String field) {
    final value = fields[field];
    if (value is! Map) return const <String, Object?>{};
    return value.cast<String, Object?>();
  }

  /// 取字符串数组字段（非字符串条目被忽略）。
  List<String> strings(String field) {
    final value = fields[field];
    if (value is! List) return const <String>[];
    final result = <String>[];
    for (final item in value) {
      if (item is String) result.add(item);
    }
    return result;
  }

  /// 覆盖单个字段后的新内容。
  DictionaryContent withField(String field, Object? value) =>
      DictionaryContent(<String, Object?>{...fields, field: value});

  /// 按 `word_contents` 列名编码为 JSON 文本。
  ///
  /// 只输出 [contentColumnNames] 里登记过的字段；未登记的键不会写库。
  Map<String, String> toJsonColumns() {
    final result = <String, String>{};
    for (final field in contentFields) {
      final column = contentColumnNames[field];
      if (column == null) continue;
      result[column] = jsonText(fields[field]);
    }
    return result;
  }
}

/// 空内容（与 `word_contents` 的列默认值一致）。
DictionaryContent emptyDictionaryContent() =>
    const DictionaryContent(<String, Object?>{
      'definitions': <Object?>[],
      'pronunciations': <Object?>[],
      'examples': <Object?>[],
      'phrases': <Object?>[],
      'forms': <Object?>[],
      'synonyms': <Object?>[],
      'antonyms': <Object?>[],
      'wordFamily': <Object?>[],
      'confusedWords': <Object?>[],
      'roots': <Object?>[],
      'affixes': <Object?>[],
      'summary': <String, Object?>{
        'shortDefinition': null,
        'translation': null,
        'cefrLevel': null,
        'frequency': null,
      },
      'learning': <String, Object?>{
        'pronunciationTip': null,
        'mnemonic': null,
        'commonMistakes': <Object?>[],
      },
      'sentenceAnalysis': <String, Object?>{
        'grammarPattern': null,
        'grammarExplanation': null,
        'grammarNotes': <Object?>[],
        'keyExpressions': <Object?>[],
        'similarExamples': <Object?>[],
        'variations': <Object?>[],
      },
      'tags': <Object?>[],
    });

/// 数组字段的并集去重键。
///
/// 键的粒度决定「什么算重复」：释义按 `语言|词性|文本`，音标按
/// `口音|音标|音频`，例句只按句子本身。旧版 `merge.ts` 逐个字段硬编码了
/// 这套规则，这里集中成一处以便单测逐条覆盖。
String arrayItemKey(String field, Map<String, Object?> item) {
  switch (field) {
    case 'definitions':
      return '${_text(item['language'])}|${_text(item['partOfSpeech'])}'
          '|${_lower(_text(item['text']))}';
    case 'pronunciations':
      return '${_text(item['accent'])}|${_text(item['phonetic'])}'
          '|${_text(item['audioUrl'])}';
    case 'examples':
      return _lower(_text(item['sentence']));
    case 'phrases':
      return '${_lower(_text(item['phrase']))}|${_text(item['translation'])}';
    case 'forms':
      return '${_text(item['type'])}|${_lower(_text(item['value']))}';
    case 'synonyms':
    case 'antonyms':
    case 'wordFamily':
    case 'confusedWords':
      return _lower(_text(item['word']));
    case 'roots':
      return '${_lower(_text(item['root']))}|${_lower(_text(item['meaning']))}';
    case 'affixes':
      return '${_text(item['type'])}|${_lower(_text(item['value']))}';
    default:
      return _text(item['value']);
  }
}

/// 该条目是否是用户产出（手工编辑的释义 / 手工添加的例句）。
///
/// 合并与强制覆盖时用户内容永远保留——旧版在
/// `mergeRequestedFields` 与 `preserveUserContent` 两处重复了这条规则。
bool isUserProtectedItem(String field, Map<String, Object?> item) {
  if (field == 'definitions') return item['isUserEdited'] == true;
  if (field == 'examples') return item['isUserAdded'] == true;
  return false;
}

/// 把任意值编码为 JSON 文本。
String jsonText(Object? value) => jsonEncode(value);

String _text(Object? value) => value is String ? value.trim() : '';

String _lower(String value) => value.toLowerCase();
