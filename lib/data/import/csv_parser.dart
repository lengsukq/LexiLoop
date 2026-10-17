/// EasyDict CSV 的解析。
///
/// 对应旧版 `app/api/imports/preview/route.ts` + `modules/imports/parser.ts`。
///
/// **与旧版的差异**：旧版把预览令牌持久化到 `import_previews` 表；
/// 本版把预览直接写进 `import_batches` / `import_rows`（见
/// `CsvImportService.preview`），因此解析层只需要产出**行模型**，
/// 不关心存储。
///
/// 解析层不查库：行内重复（`DUPLICATE`）在这里判定，
/// 与库中已有词条重复（`EXISTING`）必须等 `CsvImportService` 查库后补标。
library;

import 'package:csv/csv.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/html_text.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/data/import/csv_columns.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

/// 一行解析结果。
class ParsedCsvRow {
  /// 以各字段构造。
  const new({
    required this.rowNumber,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.examples,
    required this.phrases,
    required this.synonyms,
    required this.antonyms,
    required this.roots,
    required this.affixes,
    required this.wordFamilies,
    required this.confusedWords,
    required this.tags,
    this.definitionText,
    this.phonetic,
    this.status = ImportRowStatus.newWord,
    this.errorMessage,
    this.errorCode,
  });

  /// 数据行序号，从 1 起（不含表头）。
  final int rowNumber;

  /// 词条文本（保留 CSV 中的原始大小写与空白压缩结果）。
  final String term;

  /// 归一化词条文本，唯一性判定的基准。
  final String normalizedTerm;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型判定结果。
  final LexicalContentType contentType;

  /// 释义文本。
  final String? definitionText;

  /// 音标。
  final String? phonetic;

  /// 例句列表。
  final List<String> examples;

  /// 短语列表。
  final List<String> phrases;

  /// 同义词列表。
  final List<String> synonyms;

  /// 反义词列表。
  final List<String> antonyms;

  /// 词根列表。
  final List<String> roots;

  /// 词缀列表。
  final List<String> affixes;

  /// 词族列表。
  final List<String> wordFamilies;

  /// 易混词列表。
  final List<String> confusedWords;

  /// 标签列表。
  final List<String> tags;

  /// 处理状态（解析层只会给出 [ImportRowStatus.newWord] /
  /// [ImportRowStatus.duplicate] / [ImportRowStatus.invalid]）。
  final ImportRowStatus status;

  /// 非法行的原因文案；合法行为 `null`。
  final String? errorMessage;

  /// 非法行的错误码，用于写回 `import_rows.error_code`。
  final AppErrorCode? errorCode;

  /// 该行是否可以参与导入。
  bool get isValid => errorMessage == null;

  /// 该行是否需要用户注意（非法或重复）。
  bool get needsAttention => status != ImportRowStatus.newWord;

  /// 复制一份并替换状态。
  ///
  /// 存在的意义：解析层判不了 `EXISTING`，只能由服务层查库后回填状态。
  ParsedCsvRow copyWithStatus(ImportRowStatus status) => ParsedCsvRow(
    rowNumber: rowNumber,
    term: term,
    normalizedTerm: normalizedTerm,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: contentType,
    definitionText: definitionText,
    phonetic: phonetic,
    examples: examples,
    phrases: phrases,
    synonyms: synonyms,
    antonyms: antonyms,
    roots: roots,
    affixes: affixes,
    wordFamilies: wordFamilies,
    confusedWords: confusedWords,
    tags: tags,
    status: status,
    errorMessage: errorMessage,
    errorCode: errorCode,
  );

  /// 序列化为 `import_rows.raw_json`。
  ///
  /// 语言方向也要存：`import_batches` / `import_rows` 都没有语言列，
  /// 而提交时必须知道往哪个语言方向写词条。
  Map<String, Object?> toJson() => <String, Object?>{
    'rowNumber': rowNumber,
    'term': term,
    'normalizedTerm': normalizedTerm,
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'contentType': contentType.wire,
    'status': status.wire,
    'definition': definitionText,
    'phonetic': phonetic,
    'examples': examples,
    'phrases': phrases,
    'synonyms': synonyms,
    'antonyms': antonyms,
    'roots': roots,
    'affixes': affixes,
    'wordFamilies': wordFamilies,
    'confusedWords': confusedWords,
    'tags': tags,
    'errorCode': errorCode?.code,
    'errorMessage': errorMessage,
  };

  /// 从 `import_rows.raw_json` 还原。
  ///
  /// 结构损坏时返回 `null` 而不是抛错：一行坏数据不该让整批无法提交，
  /// 调用方会把它标为 `ERROR`。
  static ParsedCsvRow? fromJson(Map<String, Object?> json) {
    final term = json['term'];
    final rowNumber = json['rowNumber'];
    if (term is! String || rowNumber is! num) return null;
    return ParsedCsvRow(
      rowNumber: rowNumber.toInt(),
      term: term,
      normalizedTerm: json['normalizedTerm'] as String? ?? term,
      sourceLanguage: json['sourceLanguage'] as String? ?? '',
      targetLanguage: json['targetLanguage'] as String? ?? '',
      contentType:
          wireLookup(
            LexicalContentType.values,
            json['contentType'] as String? ?? '',
          ) ??
          LexicalContentType.word,
      definitionText: json['definition'] as String?,
      phonetic: json['phonetic'] as String?,
      examples: _stringList(json['examples']),
      phrases: _stringList(json['phrases']),
      synonyms: _stringList(json['synonyms']),
      antonyms: _stringList(json['antonyms']),
      roots: _stringList(json['roots']),
      affixes: _stringList(json['affixes']),
      wordFamilies: _stringList(json['wordFamilies']),
      confusedWords: _stringList(json['confusedWords']),
      tags: _stringList(json['tags']),
      status:
          wireLookup(ImportRowStatus.values, json['status'] as String? ?? '') ??
          ImportRowStatus.newWord,
      errorMessage: json['errorMessage'] as String?,
      errorCode: AppErrorCode.fromCode(json['errorCode'] as String? ?? ''),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

/// 解析结果。
class CsvParseResult {
  /// 以行与跳过数构造。
  const new({required this.rows, required this.skippedCount});

  /// 解析出的数据行（含非法行与重复行）。
  final List<ParsedCsvRow> rows;

  /// 被整行跳过的完全空行数（不进入 [rows]，也不落库）。
  final int skippedCount;
}

/// 解析 EasyDict CSV 文本。
///
/// 抛出的错误：
/// - [AppErrorCode.csvEncodingInvalid]：内容含替换字符 U+FFFD；
/// - [AppErrorCode.csvMissingHeaders]：文件为空或缺少词条列；
/// - [AppErrorCode.csvTooManyRows]：数据行超过 [maxCsvRows]；
/// - [AppErrorCode.validationError]：语言代码缺失或超长。
///
/// 单个非法行**不抛错**，而是带上 [ParsedCsvRow.errorMessage] 返回，
/// 让用户能在预览里看到「第几行有问题」并决定是否继续。
CsvParseResult parseEasyDictCsv(
  String content, {
  required String sourceLanguage,
  required String targetLanguage,
}) {
  _assertLanguage(sourceLanguage);
  _assertLanguage(targetLanguage);
  if (content.contains('\uFFFD')) {
    throw const ValidationError(
      AppErrorCode.csvEncodingInvalid,
      details: '内容含替换字符 U+FFFD',
    );
  }

  // skipEmptyLines 必须为 false：否则无法区分「空行」与「少列的行」，
  // 行号也会与文件里的行错位。
  final table = const CsvDecoder(skipEmptyLines: false).convert(content);
  if (table.isEmpty) {
    throw const ValidationError(
      AppErrorCode.csvMissingHeaders,
      details: '文件为空',
    );
  }

  final columns = resolveCsvColumns(_cells(table.first));
  final termIndex = columns[CsvField.term];
  if (termIndex == null) {
    throw const ValidationError(
      AppErrorCode.csvMissingHeaders,
      details: '缺少词条列（单词 / word / term）',
    );
  }
  if (table.length - 1 > maxCsvRows) {
    throw ValidationError(
      AppErrorCode.csvTooManyRows,
      details: '数据行 ${table.length - 1} 超过上限 $maxCsvRows',
    );
  }

  final rows = <ParsedCsvRow>[];
  var skipped = 0;
  for (var index = 1; index < table.length; index += 1) {
    final cells = _cells(table[index]);
    if (cells.every((cell) => cell.isEmpty)) {
      skipped += 1;
      continue;
    }
    rows.add(
      _parseRow(
        cells: cells,
        rowNumber: index,
        termIndex: termIndex,
        columns: columns,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
    );
  }

  return CsvParseResult(
    rows: _markDuplicates(rows, sourceLanguage, targetLanguage),
    skippedCount: skipped,
  );
}

/// 标记文件内重复：保留首次出现，后续同键行标 `DUPLICATE`。
List<ParsedCsvRow> _markDuplicates(
  List<ParsedCsvRow> rows,
  String sourceLanguage,
  String targetLanguage,
) {
  final seen = <String>{};
  final result = <ParsedCsvRow>[];
  for (final row in rows) {
    if (!row.isValid) {
      result.add(row);
      continue;
    }
    final key = identityKey(row.normalizedTerm, sourceLanguage, targetLanguage);
    result.add(
      seen.add(key) ? row : row.copyWithStatus(ImportRowStatus.duplicate),
    );
  }
  return List<ParsedCsvRow>.unmodifiable(result);
}

ParsedCsvRow _parseRow({
  required List<String> cells,
  required int rowNumber,
  required int termIndex,
  required Map<CsvField, int> columns,
  required String sourceLanguage,
  required String targetLanguage,
}) {
  final term = _cellAt(cells, termIndex);
  final empty = _emptyRow(
    rowNumber: rowNumber,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
  );
  if (term.isEmpty) {
    return empty.withError(AppErrorCode.termRequired);
  }
  if (term.length > termMaxLength) {
    return empty.withError(AppErrorCode.termTooLong);
  }

  final contentType = detectContentType(term);
  return ParsedCsvRow(
    rowNumber: rowNumber,
    term: term,
    normalizedTerm: normalizeTerm(term, sourceLanguage),
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: contentType,
    definitionText: _optionalText(cells, columns, CsvField.definition),
    phonetic: _optionalText(cells, columns, CsvField.phonetic),
    examples: _list(cells, columns, CsvField.examples),
    phrases: _list(cells, columns, CsvField.phrases),
    synonyms: _list(cells, columns, CsvField.synonyms),
    antonyms: _list(cells, columns, CsvField.antonyms),
    roots: _list(cells, columns, CsvField.roots),
    affixes: _list(cells, columns, CsvField.affixes),
    wordFamilies: _list(cells, columns, CsvField.wordFamilies),
    confusedWords: _list(cells, columns, CsvField.confusedWords),
    tags: _list(cells, columns, CsvField.tags),
  );
}

ParsedCsvRow _emptyRow({
  required int rowNumber,
  required String sourceLanguage,
  required String targetLanguage,
}) {
  return ParsedCsvRow(
    rowNumber: rowNumber,
    term: '',
    normalizedTerm: '',
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: LexicalContentType.word,
    examples: const <String>[],
    phrases: const <String>[],
    synonyms: const <String>[],
    antonyms: const <String>[],
    roots: const <String>[],
    affixes: const <String>[],
    wordFamilies: const <String>[],
    confusedWords: const <String>[],
    tags: const <String>[],
    status: ImportRowStatus.invalid,
  );
}

/// 把行标为非法。
extension on ParsedCsvRow {
  ParsedCsvRow withError(AppErrorCode code) => ParsedCsvRow(
    rowNumber: rowNumber,
    term: term,
    normalizedTerm: normalizedTerm,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: contentType,
    examples: examples,
    phrases: phrases,
    synonyms: synonyms,
    antonyms: antonyms,
    roots: roots,
    affixes: affixes,
    wordFamilies: wordFamilies,
    confusedWords: confusedWords,
    tags: tags,
    status: ImportRowStatus.invalid,
    errorCode: code,
    errorMessage: code.defaultMessage,
  );
}

/// 把一行原始单元格拍平成字符串。
///
/// **必须在这里解一次 HTML 实体**：EasyDict 导出的释义与例句里带着
/// `&amp;` / `&#x27;` / `&quot;` 这类实体（它的抓取结果来自 HTML 文本，
/// 转义没有还原）。不还原就原样进库、原样出现在单词本与词条详情里——
/// 用户看到的是「降水是&amp; 挤出」这种夹着符号的句子。
///
/// 边界选在**解析层**而不是展示层：库里的数据应当是干净的；让每个展示
/// 组件各自兜底，同一份数据就会在不同页面显示成不同样子。
List<String> _cells(List<dynamic> row) => row
    .map((cell) => decodeHtmlEntities(cell?.toString().trim() ?? ''))
    .toList(growable: false);

String _cellAt(List<String> cells, int index) =>
    index < cells.length ? cells[index] : '';

String? _optionalText(
  List<String> cells,
  Map<CsvField, int> columns,
  CsvField field,
) {
  final index = columns[field];
  if (index == null) return null;
  final value = _cellAt(cells, index);
  return value.isEmpty ? null : value;
}

List<String> _list(
  List<String> cells,
  Map<CsvField, int> columns,
  CsvField field,
) {
  final index = columns[field];
  if (index == null) return const <String>[];
  return splitCsvList(
    _cellAt(cells, index),
    splitCommas: commaSplitFields.contains(field),
  );
}

void _assertLanguage(String language) {
  if (language.isEmpty || language.length > languageFieldMaxLength) {
    throw ValidationError(
      AppErrorCode.validationError,
      details: '语言代码不合法：$language',
    );
  }
}
