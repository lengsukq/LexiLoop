/// 局域网增量同步的载荷模型与编解码契约。
///
/// 与全量备份 `lexiloop-json-backup` 分开的原因：
/// 1. 增量包只包含参与同步的 8 张业务表（跳过 4 张本机审计/任务表与 3 张派生表）；
/// 2. 附带轻量的 `word_refs` 身份映射，让引用老词的新日志/新会话无需携带庞大的
///    `word_contents`（省去 85%–95% 体积）；
/// 3. 携带导出端自身时钟 `serverNow` 与 `datasetEpoch`，彻底隔离跨设备时钟偏差。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';

/// 参与增量同步的 8 张业务表（父表优先）。
const List<String> incrementalSyncTableOrder = <String>[
  'words',
  'word_contents',
  'study_sessions',
  'study_session_items',
  'review_logs',
  'settings',
  'word_packs',
  'word_pack_items',
];

/// 一份增量（或精简全量）同步载荷。
class IncrementalSyncPayload {
  /// 以元信息、词条引用映射与表数据构造。
  const new({
    required this.isIncremental,
    required this.serverNow,
    required this.datasetEpoch,
    required this.wordRefs,
    required this.tables,
    this.since,
  });

  /// 是否基于水位线的增量切片；`false` 表示首次同步或纪元变更后的精简全量包。
  final bool isIncremental;

  /// 导出端在事务快照时刻的本机时钟（epoch 毫秒），供对端记为下次 `since`。
  final int serverNow;

  /// 导出端当前的数据集纪元。
  final String datasetEpoch;

  /// 本次导出使用的起始水位（全量时为 `null`）。
  final int? since;

  /// 本次增量引用到、但本身未变更的老词最小身份存根。
  final List<Map<String, Object?>> wordRefs;

  /// 按表名索引的待同步行数据（键集合恒为 [incrementalSyncTableOrder]）。
  final Map<String, List<Map<String, Object?>>> tables;

  /// 载荷中实际包含的数据总行数（不含辅助 `wordRefs`）。
  int get totalRows => tables.values.fold(0, (sum, rows) => sum + rows.length);

  /// 编码为可序列化 JSON 信封。
  Map<String, Object?> toEnvelope() => <String, Object?>{
    'format': lanSyncDeltaFormat,
    'version': lanSyncDeltaVersion,
    'mode': isIncremental ? 'delta' : 'full',
    'serverNow': serverNow,
    'datasetEpoch': datasetEpoch,
    if (since != null) 'since': since,
    'word_refs': wordRefs,
    for (final table in incrementalSyncTableOrder)
      table: tables[table] ?? const <Map<String, Object?>>[],
  };
}

/// 解析增量同步信封；格式不合法时抛 [ValidationError]。
IncrementalSyncPayload parseIncrementalSyncPayload(
  Map<String, Object?> decoded,
) {
  if (decoded['format'] != lanSyncDeltaFormat || decoded['version'] is! num) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  final serverNow = decoded['serverNow'];
  if (serverNow is! num) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  final epoch = decoded['datasetEpoch'];
  final mode = decoded['mode'];
  final sinceRaw = decoded['since'];

  final tables = <String, List<Map<String, Object?>>>{
    for (final table in incrementalSyncTableOrder)
      table: _parseRows(table, decoded[table]),
  };
  return IncrementalSyncPayload(
    isIncremental: mode == 'delta',
    serverNow: serverNow.round(),
    datasetEpoch: epoch is String ? epoch.trim() : '',
    since: sinceRaw is num ? sinceRaw.round() : null,
    wordRefs: _parseRows('word_refs', decoded['word_refs']),
    tables: tables,
  );
}

List<Map<String, Object?>> _parseRows(String name, Object? value) {
  if (value == null) return const <Map<String, Object?>>[];
  if (value is! List) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '增量字段 $name 不是数组',
    );
  }
  final rows = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is! Map) {
      throw ValidationError(
        AppErrorCode.backupInvalidFormat,
        details: '增量字段 $name 含非法行',
      );
    }
    rows.add(<String, Object?>{
      for (final entry in item.entries)
        if (entry.key is String) entry.key as String: entry.value,
    });
  }
  return rows;
}
