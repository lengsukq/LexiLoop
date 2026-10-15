/// EasyDict CSV 的列名映射。
///
/// **为什么列名要宽松匹配**：EasyDict 在不同版本里导出的表头既有中文
/// （`单词` / `释义`）也有英文（`word` / `definition`），大小写与空格也不
/// 统一（`Word Family` / `word_family` / `wordFamily`）。旧版按精确表头匹配，
/// 换个导出模板就整批报「缺少必要列」。
///
/// 归一化规则：去掉 BOM、转小写、删除空格/下划线/连字符/全角空格。
/// 于是 `Word Family`、`word_family`、`wordfamily` 三种写法归一后相同。
library;

/// CSV 中可映射的字段。
enum CsvField {
  /// 词条文本（唯一必需列）。
  term,

  /// 释义 / 翻译。
  definition,

  /// 音标。
  phonetic,

  /// 例句。
  examples,

  /// 短语 / 搭配。
  phrases,

  /// 同义词（含近义词）。
  synonyms,

  /// 反义词。
  antonyms,

  /// 词根。
  roots,

  /// 词缀（前缀 / 后缀）。
  affixes,

  /// 词族 / 同根词。
  wordFamilies,

  /// 易混词。
  confusedWords,

  /// 标签 / 分类。
  tags,
}

/// 每个字段接受的表头别名（已按 [normalizeCsvHeader] 归一）。
const Map<CsvField, List<String>> csvFieldAliases = <CsvField, List<String>>{
  CsvField.term: <String>[
    '单词',
    '词条',
    'word',
    'term',
    'headword',
    'spelling',
    'querytext',
    'wordtext',
  ],
  CsvField.definition: <String>[
    '释义',
    '翻译',
    '中文',
    '中文释义',
    '解释',
    'definition',
    'meaning',
    'translation',
    'trans',
    'def',
  ],
  CsvField.phonetic: <String>[
    '音标',
    '发音',
    'phonetic',
    'phonetics',
    'pronunciation',
    'ipa',
  ],
  CsvField.examples: <String>[
    '例句',
    '例句s',
    'example',
    'examples',
    'sentence',
    'sentences',
  ],
  CsvField.phrases: <String>['短语', '词组', '搭配', 'phrase', 'phrases'],
  CsvField.synonyms: <String>['同义词', '近义词', 'synonym', 'synonyms'],
  CsvField.antonyms: <String>['反义词', 'antonym', 'antonyms'],
  CsvField.roots: <String>['词根', 'root', 'roots'],
  CsvField.affixes: <String>[
    '词缀',
    '前后缀',
    '前缀',
    '后缀',
    'affix',
    'affixes',
    'prefix',
    'suffix',
  ],
  CsvField.wordFamilies: <String>[
    '词族',
    '同根词',
    '派生词',
    'wordfamily',
    'wordfamilies',
    'family',
  ],
  CsvField.confusedWords: <String>[
    '易混词',
    '形近词',
    'confused',
    'confusedwords',
    'confusable',
    'similarwords',
  ],
  CsvField.tags: <String>['标签', '分类', 'tag', 'tags', 'category'],
};

/// 归一化表头：去 BOM、转小写、删除空白与连接符号。
String normalizeCsvHeader(String header) {
  var result = header.trim();
  if (result.startsWith('\uFEFF')) result = result.substring(1);
  return result.toLowerCase().replaceAll(RegExp(r'[\s_\-/\u3000]+'), '').trim();
}

/// 把表头行解析为「字段 → 列下标」。
///
/// 同一字段出现多列时取**最靠左**的一列；无法识别的列被忽略
/// （EasyDict 常有 `序号`、`难度` 这类我们不消费的列）。
Map<CsvField, int> resolveCsvColumns(List<String> header) {
  final result = <CsvField, int>{};
  for (var index = 0; index < header.length; index += 1) {
    final normalized = normalizeCsvHeader(header[index]);
    if (normalized.isEmpty) continue;
    for (final entry in csvFieldAliases.entries) {
      if (result.containsKey(entry.key)) continue;
      if (entry.value.contains(normalized)) {
        result[entry.key] = index;
        break;
      }
    }
  }
  return result;
}

/// 需要按逗号切分的字段。
///
/// 例句与短语**不在此列**：`He said, "hi"` 这类例句内部本来就有逗号，
/// 按逗号切会把一句话劈成两条。
const Set<CsvField> commaSplitFields = <CsvField>{
  CsvField.synonyms,
  CsvField.antonyms,
  CsvField.roots,
  CsvField.affixes,
  CsvField.wordFamilies,
  CsvField.confusedWords,
  CsvField.tags,
};

/// 把单元格拆成多条取值。
///
/// 换行、分号（中英文）、竖线与顿号恒为分隔符；[splitCommas] 为真时
/// 逗号（中英文）也算——仅用于词表类字段。
List<String> splitCsvList(String raw, {required bool splitCommas}) {
  final pattern = splitCommas
      ? RegExp(r'[\n\r;；|、,，]+')
      : RegExp(r'[\n\r;；|、]+');
  return raw
      .split(pattern)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
