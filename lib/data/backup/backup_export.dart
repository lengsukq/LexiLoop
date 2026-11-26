/// JSON 备份的导出。
///
/// 与 `BackupImporter` 是同一份格式的两端：信封字段、12 张表、列名与枚举的
/// `wire` 字符串全部由 [BackupImporter] 定义。这里只负责产出**能被它读回去**
/// 的形状——凡是这个导入器不会接受的东西，一律不写进文件。
///
/// **表顺序直接复用 [BackupImporter.tableOrder]**（父表在前），而不是另抄
/// 一份。导入端在同一个事务里按这个顺序插入，导出的文件因此自带
/// 「父表先于子表」的结构：人工检查、`jq` 逐步回放都不会撞上外键约束。
///
/// **为什么用 `SELECT *` 而不是逐表硬编码列**：Drift 的列名就是下划线形式，
/// 而导入端按「备份列 ∩ 目标表实际列」过滤。让导出端跟着 schema 走，
/// 新增一列时不必同步改两处；落后版本的备份里多出来的列会被导入端忽略。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

/// 备份格式的版本号。
///
/// 沿用旧版 `src/modules/backups/service.ts` 的 `3`：版本号描述的是**备份的
/// 形状**（哪几张表、每张表哪些列），与产出它的存储引擎无关。保持不变意味着
/// 旧版的 `restoreJsonBackup` 也能读本版导出的文件，反之亦然。
const int backupVersion = 3;

/// 备份文件的 MIME 类型。
///
/// 分享时声明它，`share_plus` 才能让系统把接收方按「JSON 文件」处理而不是
/// 当成一段普通文本。
const String backupMimeType = 'application/json';

/// 写进信封 `database` 字段的取值。
///
/// 旧版恒为 `postgresql`；本版落 SQLite。导入端不读这个字段，它只对人有用。
const String backupDatabaseFlavor = 'sqlite';

/// 刻意**不**导出的表。
///
/// 这两张表都不在 [BackupImporter.tableOrder] 里，把它们写进文件只会带来
/// 坏处，因此导出端与导入端必须同时排除：
///
/// - `game_high_scores`：本版的计分公式已重构（统一 `scoring.dart`、速度
///   奖励、连击上限、S/A/B/C 评级），与旧版历史分不可比。带着旧分回来，用户
///   只会对着一串永远刷不破的记录困惑；
/// - `word_review_stats`：它是由 `review_logs` 物化出来的聚合表，导入事务的
///   末尾会按 `review_logs` 重算，写进去的值当场就被覆盖。
///
/// `daily_ai_suggestions` 同样不在导出范围内：它是按天缓存的可重新生成数据，
/// 旧版备份本来就不含它。
const List<String> tablesExcludedFromExport = <String>[
  'game_high_scores',
  'word_review_stats',
];

/// 导出结果。
class BackupExportResult {
  /// 以 UTF-8 字节、各表行数与逻辑数据指纹构造。
  const new({
    required this.bytes,
    required this.rowCounts,
    this.fingerprint = '',
  });

  /// 备份文件的 UTF-8 字节。
  ///
  /// 落盘、分享与大小上限都用字节；字符串只在测试里按需解码，
  /// 避免 27MB 的备份在内存里同时存在一份 `String` 和一份 `Uint8List`。
  final Uint8List bytes;

  /// 各表导出的行数。
  final Map<String, int> rowCounts;

  /// 导出逻辑数据的稳定 SHA-256；不包含信封导出时间。
  final String fingerprint;

  /// 导出的总行数。
  int get totalRows => rowCounts.values.fold(0, (sum, count) => sum + count);
}

/// JSON 备份的导出器。
class BackupExporter {
  /// 以数据库构造导出器。
  const new(this._db);

  final AppDatabase _db;

  /// 本导出器产出的表顺序（父表在前）。
  ///
  /// 只是 [BackupImporter.tableOrder] 的别名，存在的意义是让调用方不必为了
  /// 打印「导出了哪几张表」而依赖导入器。
  static const List<String> tableOrder = BackupImporter.tableOrder;

  /// 把整库导出为备份文件的字节。
  ///
  /// 超过 [maxBackupBytes] 时抛 [AppErrorCode.backupTooLarge]，与
  /// [BackupImporter] 的拒绝条件一致——导出器多拒的那部分只是「字节数比字符
  /// 数大」的文件，两边不会各自接受对方产不出的东西。
  Future<BackupExportResult> exportToJson({
    bool includeFingerprint = false,
  }) async {
    final tables = await readAllTables();
    _stripSecrets(tables);
    final bytes = utf8.encode(jsonEncode(_envelope(tables)));
    if (bytes.length > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '导出结果 ${bytes.length} 字节，上限 $maxBackupBytes',
      );
    }
    final fingerprint = includeFingerprint ? _fingerprint(tables) : '';
    return BackupExportResult(
      bytes: bytes,
      fingerprint: fingerprint,
      rowCounts: <String, int>{
        for (final entry in tables.entries) entry.key: entry.value.length,
      },
    );
  }

  /// 按 [tableOrder] 逐表读出全部行（**原样，不剥密码**）。
  ///
  /// **为什么公开且不剥密码**：合并同步需要本机行的原值——它不把数据发出去，
  /// 而是拿本机行与收到的行做合并再写回库里。若读出来的行已经被剥掉
  /// WebDAV 密码，合并写回时那个密码就被抹掉了。
  ///
  /// 剥密码是**导出**这一个动作的事，因此挪到了 [exportToJson] 里、
  /// 读表之后，而不是读表的时候。
  Future<Map<String, List<Map<String, Object?>>>> readAllTables() =>
      _db.transaction(() async {
        final tables = <String, List<Map<String, Object?>>>{};
        for (final table in tableOrder) {
          final rows = await _db.customSelect('SELECT * FROM $table').get();
          tables[table] = rows
              .map((row) => _rowToJson(row.data))
              // **必须是可增长列表**：合并同步会就地往这些列表里追加远端行，
              // 再整份交给导入事务。固定的列表会让那条路径当场抛异常。
              .toList();
        }
        return tables;
      });

  /// 对导出的逻辑数据计算稳定指纹。
  ///
  /// 表行与对象键的顺序不影响指纹；`exportedAt` 不参与输入。WebDAV 成功/失败
  /// 状态以及对应设置行的 `updated_at` 也不属于备份内容的变化。
  String _fingerprint(Map<String, List<Map<String, Object?>>> tables) {
    final canonicalTables = <String, Object?>{};
    final tableNames = tables.keys.toList()..sort();
    for (final table in tableNames) {
      final rows = tables[table]!.map((row) {
        final canonicalRow = Map<String, Object?>.from(row);
        if (table == 'settings' && canonicalRow['key'] == webdavSettingsKey) {
          canonicalRow.remove('updated_at');
          final value = _decodeSettingValue(canonicalRow['value_json']);
          if (value is Map) {
            final stableValue = _canonicalize(<String, Object?>{
              for (final entry in value.entries)
                if (entry.key is String &&
                    !const <String>{
                      'lastSuccessAt',
                      'lastError',
                      'lastCheckpoint',
                    }.contains(entry.key))
                  entry.key as String: entry.value,
            });
            canonicalRow['value_json'] = jsonEncode(stableValue);
          }
        } else if (table == 'settings' &&
            canonicalRow['key'] == cloudSyncSettingsKey) {
          canonicalRow.remove('updated_at');
          final value = _decodeSettingValue(canonicalRow['value_json']);
          if (value is Map) {
            canonicalRow['value_json'] = jsonEncode(
              _canonicalize(cloudSyncValueForFingerprint(value)),
            );
          }
        }
        return _canonicalize(canonicalRow);
      }).toList()..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      canonicalTables[table] = rows;
    }
    return sha256.convert(utf8.encode(jsonEncode(canonicalTables))).toString();
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.whereType<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }

  /// 从导出行里去掉不应外流的凭据。
  ///
  /// 只处理 `settings` 表的 `webdavBackup` 一个键：`llmConfig` 里的 API Key
  /// 保持原样，因为「换机迁移」本来就是导出备份的主要用途之一，
  /// 而 WebDAV 密码是唯一一个「文件本身会被送到凭据所属的那台服务器」的情况。
  void _stripSecrets(Map<String, List<Map<String, Object?>>> tables) {
    final rows = tables['settings'];
    if (rows == null) return;
    for (final row in rows) {
      final key = row['key'];
      if (key == webdavSettingsKey) {
        final decoded = _decodeSettingValue(row['value_json']);
        if (decoded != null) {
          row['value_json'] = jsonEncode(webdavValueForExport(decoded));
        }
      } else if (key == cloudSyncSettingsKey) {
        final decoded = _decodeSettingValue(row['value_json']);
        if (decoded != null) {
          row['value_json'] = jsonEncode(cloudSyncValueForExport(decoded));
        }
      }
    }
  }

  /// 解析 `settings.value_json` 这一列；不是合法 JSON 时返回 `null`。
  Object? _decodeSettingValue(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  /// 包一层信封。
  ///
  /// 信封里的 `exportedAt` 是 ISO-8601 字符串，行内的时间戳才是 epoch 毫秒
  /// —— 这与真实备份（`lexiloop-backup-*.json`）一致：信封给人读，机器读行。
  ///
  /// 旧版的 `appVersion` / `schemaVersion` / `migrations` 不再写出：它们描述
  /// 的是 PostgreSQL 迁移链，本版没有对应物，写一个空壳只会误导。
  Map<String, Object?> _envelope(
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    return <String, Object?>{
      'format': backupFormat,
      'version': backupVersion,
      'database': backupDatabaseFlavor,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      for (final entry in tables.entries) entry.key: entry.value,
    };
  }

  /// 一行转成可直接 `jsonEncode` 的映射。
  Map<String, Object?> _rowToJson(Map<String, Object?> data) {
    final result = <String, Object?>{};
    for (final entry in data.entries) {
      result[entry.key] = _cell(entry.key, entry.value);
    }
    return result;
  }

  /// 单个单元格的值。
  ///
  /// SQLite 返回的就是列的实际存储形态，因此这一层几乎是恒等的：
  /// - 枚举列经 `WireEnumConverter` 存成大写下划线字符串，原样带走即 `wire`；
  /// - 时间戳列本来就是 epoch 毫秒整数，原样带走仍是整数；
  /// - `null` 原样保留，导入端的列交集过滤不会把 `null` 当成「缺列」。
  ///
  /// **唯一的例外是 BLOB**：`Uint8List` 实现了 `List<int>`，`jsonEncode` 会
  /// 把它静默编成一个数字数组，回灌时列类型不匹配且无人察觉。当前 12 张表里
  /// 没有 BLOB 列，这里显式拒绝，是为了让将来加表时有人看见这里的报错，
  /// 而不是拿到一份悄悄损坏的备份。
  Object? _cell(String column, Object? value) {
    if (value == null || value is String || value is num) return value;
    if (value is bool) return value;
    if (value is Uint8List) {
      throw ValidationError(
        AppErrorCode.backupInvalidFormat,
        details: '列 $column 是 BLOB，JSON 备份无法无损表达',
      );
    }
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '列 $column 的类型 ${value.runtimeType} 无法写入 JSON 备份',
    );
  }
}
