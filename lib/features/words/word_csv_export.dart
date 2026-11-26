/// 单词本 CSV 导出工具（UTF-8 BOM + EasyDict 兼容表头）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/services/backup/backup_file.dart';

/// 导出 CSV 的 MIME 类型。
const String wordCsvMimeType = 'text/csv; charset=utf-8';

/// 把词条列表编码为带 UTF-8 BOM 的 RFC 4180 CSV 文本。
///
/// 表头采用 EasyDict 与本应用均能直接识别的标准中文列名，导出后可直接
/// 用 Excel 打开（BOM 防止中文乱码），也可再次无损导回 LexiLoop。
String encodeWordsCsv(List<WordExportRow> rows) {
  final buffer = StringBuffer('\uFEFF单词,音标,释义,例句,标签,备注\r\n');
  for (final row in rows) {
    final fields = <String>[
      row.term,
      row.phonetic,
      row.definitions.join('；'),
      row.examples.join('\n'),
      row.tags.join(';'),
      row.note,
    ];
    buffer
      ..write(fields.map(_escapeCsvField).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

/// 生成带时间戳的导出文件名。
String buildWordsExportFileName(DateTime now) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final date = '${now.year}${pad(now.month)}${pad(now.day)}';
  final time = '${pad(now.hour)}${pad(now.minute)}';
  return 'lexiloop-words-$date-$time.csv';
}

/// 导出并交付 CSV 文件给系统分享面板 / 浏览器下载。
Future<String> shareWordsCsv(List<WordExportRow> rows, {DateTime? now}) {
  final csvText = encodeWordsCsv(rows);
  final bytes = Uint8List.fromList(utf8.encode(csvText));
  final fileName = buildWordsExportFileName(now ?? DateTime.now());
  return shareBackupBytes(
    bytes: bytes,
    fileName: fileName,
    mimeType: wordCsvMimeType,
    subject: 'LexiLoop 词库导出',
  );
}

String _escapeCsvField(String value) {
  if (!value.contains(',') &&
      !value.contains('"') &&
      !value.contains('\n') &&
      !value.contains('\r')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}
