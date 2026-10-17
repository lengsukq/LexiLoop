/// 把一份对端备份合并进本机数据库。
///
/// 三件事按顺序发生：
/// 1. 解析远端负载（与本地导入同一套校验）；
/// 2. 读出本机 12 张表，和远端行**在内存里**合并（纯函数，见
///    `backup_merge.dart`）；
/// 3. 把合并结果交给导入器的单事务替换（见 `BackupImporter.replaceAll`）。
///
/// **为什么复用导入器的写事务**：它是全应用唯一一处「整表写入」的实现，
/// 已经被 30 多个备份用例覆盖。合并自己再写一堆 INSERT/UPDATE，等于把
/// 「可能写坏学习数据」的面积翻一倍。
///
/// **为什么整库读进内存**：合并的正确性依赖「本机已有哪些行」这个全局视图
/// （身份映射、去重集合、id 游标）。分批查库能把内存压下来，但会让每一步都
/// 变成一次 IO + 一次一致性假设。真实备份约 27MB，本机行与远端行各一份，
/// 与"先导出再导入"同一量级——这是刻意的取舍，写在 `docs/LAN_SYNC.md` 里。
library;

import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/merge/backup_merge.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 合并同步的执行入口。
class BackupMergeService {
  /// 以导出器（读本机行）、导入器（写回）与设置服务构造。
  ///
  /// `clock` 是可测性接缝：合并时间决定 14/30 天窗口的基准与重算行的
  /// `updated_at`，测试里注入固定值才能断言。
  new(this._exporter, this._importer, this._settings, {int Function()? clock})
    : _clock = clock ?? _wallClockMs;

  final BackupExporter _exporter;
  final BackupImporter _importer;
  final SettingsService _settings;
  final int Function() _clock;

  /// 合并 [raw] 并写回本机，返回合并结果与计数。
  ///
  /// 失败时本机数据不变：解析在写之前，写在导入器的单事务里。
  Future<MergeOutcome> merge(String raw) async {
    final remote = parseBackupPayload(raw);
    final local = await _exporter.readAllTables();
    final settings = await _settings.load();
    final outcome = mergeBackupTables(
      local: local,
      remote: remote,
      scheduler: FsrsScheduler(
        requestRetention: settings.studyPlan.targetRetentionRate,
      ),
      now: _clock(),
    );
    await _importer.replaceAll(outcome.tables);
    return outcome;
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
