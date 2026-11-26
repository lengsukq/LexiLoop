/// 通用词表解析与自定义 CSV/TSV 列映射。
///
/// 弥补 `parseEasyDictCsv` 仅接受特定 EasyDict 表头的限制：
/// 1. 支持纯文本词表（`.txt`：每行一个词，兼容 `1. word` 编号、`word\tmeaning`、
///    `word | meaning`、Anki/欧路/墨墨/扇贝导出）；
/// 2. 支持任意 TSV 与无标准表头 CSV 的手工列映射（由界面弹窗/卡片让用户选择
///    哪一列是词条、哪一列是释义/音标/例句/标签）。
library;

import 'package:csv/csv.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/html_text.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/data/import/csv_columns.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

/// 待用户手工确认列映射的原始表格草稿。
class CsvColumnMappingDraft {
  /// 以文件名、原文、表头候选与样本行构造。
  const new({
    required this.filename,
    required this.content,
    required this.headers,
    required this.sampleRows,
    this.delimiter = ',',
  });

  /// 文件名。
  final String filename;

  /// 文件原始文本。
  final String content;

  /// 首行单元格（或生成的列标签）。
  final List<String> headers;

  /// 前若干行样本数据（供界面预览确认列含义）。
  final List<List<String>> sampleRows;

  /// 探测到的分隔符（`,` 或 `\t`）。
  final String delimiter;
}

/// 解析通用文本词表（`.txt` / `.tsv`），输出统一的 [CsvParseResult]。
///
/// 支持的常见格式：
/// - 每行一个单词（含可选序号前缀如 `1. abandon` / `2) resilient`）；
/// - 制表符分隔（Anki / 欧路 / 墨墨：`word\tmeaning` 或 `word\tphonetic\tmeaning`）；
/// - 竖线分隔（`word | meaning`）；
/// - 带标准表头的 TSV（自动按 [resolveCsvColumns] 识别列）。
CsvParseResult parseWordlistText(
  String content, {
  required String sourceLanguage,
  required String targetLanguage,
  List<String> extraTags = const <String>[],
}) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rawLines = normalized.split('\n');
  final nonEmpty = <String>[
    for (final line in rawLines)
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#'))
        line.trim(),
  ];
  if (nonEmpty.isEmpty) {
    throw const ValidationError(
      AppErrorCode.csvMissingHeaders,
      details: '词表文件为空。',
    );
  }
  if (nonEmpty.length > maxCsvRows) {
    throw ValidationError(
      AppErrorCode.csvTooManyRows,
      details: '词表共 ${nonEmpty.length} 行，超过上限 $maxCsvRows 行。',
    );
  }
  if (nonEmpty.first.contains('\t')) {
    return _parseTsvLines(
      rawLines,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      extraTags: extraTags,
    );
  }
  return _parsePlainLines(
    rawLines,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    extraTags: extraTags,
  );
}

/// 检查一段分隔符文本，生成可供用户手动映射列的 [CsvColumnMappingDraft]。
CsvColumnMappingDraft? inspectCsvForColumnMapping(
  String content, {
  required String filename,
}) {
  final delimiter = _detectDelimiter(content);
  final table = _decodeDelimited(content, delimiter);
  if (table.isEmpty) return null;
  final first = _cleanCells(table.first);
  if (first.isEmpty) return null;
  final samples = <List<String>>[
    for (var i = 0; i < table.length && i < csvColumnMappingSampleRows; i += 1)
      _cleanCells(table[i]),
  ];
  return CsvColumnMappingDraft(
    filename: filename,
    content: content,
    headers: first,
    sampleRows: samples,
    delimiter: delimiter,
  );
}

/// 按用户指定的列映射解析 CSV / TSV 文本。
CsvParseResult parseDelimitedWithColumnMap(
  String content, {
  required String sourceLanguage,
  required String targetLanguage,
  required Map<CsvField, int> columns,
  bool hasHeaderRow = true,
  String? delimiter,
  List<String> extraTags = const <String>[],
}) {
  final termIndex = columns[CsvField.term];
  if (termIndex == null) {
    throw const ValidationError(
      AppErrorCode.csvMissingHeaders,
      details: '请指定「词条」所在列。',
    );
  }
  final table = _decodeDelimited(
    content,
    delimiter ?? _detectDelimiter(content),
  );
  final start = hasHeaderRow ? 1 : 0;
  if (table.length - start > maxCsvRows) {
    throw ValidationError(
      AppErrorCode.csvTooManyRows,
      details: '数据行 ${table.length - start} 超过上限 $maxCsvRows。',
    );
  }
  final rows = <ParsedCsvRow>[];
  var skipped = 0;
  for (var i = start; i < table.length; i += 1) {
    final cells = _cleanCells(table[i]);
    if (cells.every((cell) => cell.isEmpty)) {
      skipped += 1;
      continue;
    }
    rows.add(
      _rowFromCells(
        cells: cells,
        rowNumber: i - start + 1,
        termIndex: termIndex,
        columns: columns,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        extraTags: extraTags,
      ),
    );
  }
  return CsvParseResult(
    rows: _dedupeRows(rows, sourceLanguage, targetLanguage),
    skippedCount: skipped,
  );
}

/// 给解析结果中的每一行追加批次标签（不改变状态与行号）。
CsvParseResult appendExtraTags(CsvParseResult parsed, List<String> extraTags) {
  final clean = _cleanTagList(extraTags);
  if (clean.isEmpty) return parsed;
  return CsvParseResult(
    skippedCount: parsed.skippedCount,
    rows: <ParsedCsvRow>[
      for (final row in parsed.rows) _withExtraTags(row, clean),
    ],
  );
}

CsvParseResult _parseTsvLines(
  List<String> rawLines, {
  required String sourceLanguage,
  required String targetLanguage,
  required List<String> extraTags,
}) {
  final firstNonEmpty = rawLines.firstWhere(
    (line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('#'),
  );
  final headerCols = resolveCsvColumns(
    firstNonEmpty.split('\t').map((cell) => cell.trim()).toList(),
  );
  if (headerCols.containsKey(CsvField.term)) {
    return parseDelimitedWithColumnMap(
      rawLines.join('\n'),
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      columns: headerCols,
      delimiter: '\t',
      extraTags: extraTags,
    );
  }
  final colCount = firstNonEmpty.split('\t').length;
  final inferred = <CsvField, int>{
    CsvField.term: 0,
    if (colCount == 2) CsvField.definition: 1,
    if (colCount >= 3) CsvField.phonetic: 1,
    if (colCount >= 3) CsvField.definition: 2,
  };
  return parseDelimitedWithColumnMap(
    rawLines.join('\n'),
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    columns: inferred,
    hasHeaderRow: false,
    delimiter: '\t',
    extraTags: extraTags,
  );
}

CsvParseResult _parsePlainLines(
  List<String> rawLines, {
  required String sourceLanguage,
  required String targetLanguage,
  required List<String> extraTags,
}) {
  final rows = <ParsedCsvRow>[];
  var skipped = 0;
  var rowNumber = 0;
  final tags = _cleanTagList(extraTags);
  for (final raw in rawLines) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      skipped += 1;
      continue;
    }
    rowNumber += 1;
    final (term, definition) = _splitPlainLine(trimmed);
    rows.add(
      _buildRow(
        rowNumber: rowNumber,
        term: term,
        definition: definition,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        tags: tags,
      ),
    );
  }
  return CsvParseResult(
    rows: _dedupeRows(rows, sourceLanguage, targetLanguage),
    skippedCount: skipped,
  );
}

(String, String?) _splitPlainLine(String line) {
  final unnumbered = line.replaceFirst(_leadingNumbering, '').trim();
  final pipeIndex = unnumbered.indexOf('|');
  if (pipeIndex > 0) {
    final term = unnumbered.substring(0, pipeIndex).trim();
    final def = unnumbered.substring(pipeIndex + 1).trim();
    return (term, def.isEmpty ? null : def);
  }
  return (unnumbered, null);
}

ParsedCsvRow _rowFromCells({
  required List<String> cells,
  required int rowNumber,
  required int termIndex,
  required Map<CsvField, int> columns,
  required String sourceLanguage,
  required String targetLanguage,
  required List<String> extraTags,
}) {
  final term = _cellAt(cells, termIndex);
  final def = _optional(cells, columns[CsvField.definition]);
  final phonetic = _optional(cells, columns[CsvField.phonetic]);
  final examples = _listField(cells, columns[CsvField.examples], commas: false);
  final rowTags = _listField(cells, columns[CsvField.tags], commas: true);
  final tags = _cleanTagList(<String>[...rowTags, ...extraTags]);
  return _buildRow(
    rowNumber: rowNumber,
    term: term,
    definition: def,
    phonetic: phonetic,
    examples: examples,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    tags: tags,
  );
}

ParsedCsvRow _buildRow({
  required int rowNumber,
  required String term,
  required String sourceLanguage,
  required String targetLanguage,
  String? definition,
  String? phonetic,
  List<String> examples = const <String>[],
  List<String> tags = const <String>[],
}) {
  final cleanTerm = term.trim();
  if (cleanTerm.isEmpty) {
    return _invalidRow(
      rowNumber: rowNumber,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      code: AppErrorCode.termRequired,
    );
  }
  if (cleanTerm.length > termMaxLength) {
    return _invalidRow(
      rowNumber: rowNumber,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      code: AppErrorCode.termTooLong,
    );
  }
  return ParsedCsvRow(
    rowNumber: rowNumber,
    term: cleanTerm,
    normalizedTerm: normalizeTerm(cleanTerm, sourceLanguage),
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: detectContentType(cleanTerm),
    definitionText: definition,
    phonetic: phonetic,
    examples: examples,
    phrases: const <String>[],
    synonyms: const <String>[],
    antonyms: const <String>[],
    roots: const <String>[],
    affixes: const <String>[],
    wordFamilies: const <String>[],
    confusedWords: const <String>[],
    tags: tags,
  );
}

ParsedCsvRow _invalidRow({
  required int rowNumber,
  required String sourceLanguage,
  required String targetLanguage,
  required AppErrorCode code,
}) => ParsedCsvRow(
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
  errorCode: code,
  errorMessage: code.defaultMessage,
);

List<ParsedCsvRow> _dedupeRows(
  List<ParsedCsvRow> rows,
  String sourceLanguage,
  String targetLanguage,
) {
  final seen = <String>{};
  final out = <ParsedCsvRow>[];
  for (final row in rows) {
    if (!row.isValid) {
      out.add(row);
      continue;
    }
    final key = identityKey(row.normalizedTerm, sourceLanguage, targetLanguage);
    out.add(
      seen.add(key) ? row : row.copyWithStatus(ImportRowStatus.duplicate),
    );
  }
  return List<ParsedCsvRow>.unmodifiable(out);
}

ParsedCsvRow _withExtraTags(ParsedCsvRow row, List<String> extra) =>
    ParsedCsvRow(
      rowNumber: row.rowNumber,
      term: row.term,
      normalizedTerm: row.normalizedTerm,
      sourceLanguage: row.sourceLanguage,
      targetLanguage: row.targetLanguage,
      contentType: row.contentType,
      definitionText: row.definitionText,
      phonetic: row.phonetic,
      examples: row.examples,
      phrases: row.phrases,
      synonyms: row.synonyms,
      antonyms: row.antonyms,
      roots: row.roots,
      affixes: row.affixes,
      wordFamilies: row.wordFamilies,
      confusedWords: row.confusedWords,
      tags: _cleanTagList(<String>[...row.tags, ...extra]),
      status: row.status,
      errorMessage: row.errorMessage,
      errorCode: row.errorCode,
    );

String _detectDelimiter(String content) {
  final firstLine = content
      .split('\n')
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
  final tabs = '\t'.allMatches(firstLine).length;
  final commas = ','.allMatches(firstLine).length;
  return tabs > commas ? '\t' : ',';
}

List<List<dynamic>> _decodeDelimited(String content, String delimiter) {
  if (delimiter == '\t') {
    return <List<dynamic>>[
      for (final line in content.replaceAll('\r\n', '\n').split('\n'))
        if (line.trim().isEmpty) const <String>[] else line.split('\t'),
    ];
  }
  return const CsvDecoder(skipEmptyLines: false).convert(content);
}

List<String> _cleanCells(List<dynamic> row) => row
    .map((cell) => decodeHtmlEntities(cell?.toString().trim() ?? ''))
    .toList(growable: false);

String _cellAt(List<String> cells, int index) =>
    index >= 0 && index < cells.length ? cells[index] : '';

String? _optional(List<String> cells, int? index) {
  if (index == null) return null;
  final value = _cellAt(cells, index);
  return value.isEmpty ? null : value;
}

List<String> _listField(
  List<String> cells,
  int? index, {
  required bool commas,
}) {
  if (index == null) return const <String>[];
  return splitCsvList(_cellAt(cells, index), splitCommas: commas);
}

List<String> _cleanTagList(List<String> tags) {
  final out = <String>[];
  for (final raw in tags) {
    final tag = raw.trim();
    if (tag.isNotEmpty && !out.contains(tag)) out.add(tag);
  }
  return List<String>.unmodifiable(out);
}

final RegExp _leadingNumbering = RegExp(r'^\d+\s*[\.\)、\)]\s*');
