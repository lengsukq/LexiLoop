/// 一次共享要交出去的东西。
///
/// **为什么是一个「取备份」的回调而不是导出器**：`BackupExporter` 在
/// `lib/services/backup/`，而本文件在 `lib/data/`。数据层依赖服务层会让
/// 分层倒过来（`lib/data` 只该认识协议与存储）。把导出收成一个
/// `Future<LanSyncBackup> Function()`，服务层在装配时把导出器接上去，
/// 数据层就只需要「拿到字节并写进响应」。
library;

import 'dart:typed_data';

/// 要传给对端的一份备份。
class LanSyncBackup {
  /// 以字节、文件名与总行数构造。
  const new({
    required this.bytes,
    required this.fileName,
    required this.totalRows,
  });

  /// 备份 JSON 的 UTF-8 字节。
  ///
  /// 用字节而不是 `String`：一份真实备份约 27MB，同时持有一份 `String`
  /// 与一份 `Uint8List` 会让峰值内存翻倍，而 HTTP 响应体本来就是字节。
  final Uint8List bytes;

  /// 与本地导出逐字一致的文件名（`lexiloop-backup-YYYY-MM-DD-HHmmss.json`）。
  final String fileName;

  /// 备份包含的总行数。
  final int totalRows;
}

/// 按需产出一份备份。
///
/// 由主机在每个拉取请求到达时调用**恰好一次**：预先导出再缓存会让
/// 「开了共享但没人来拉」也占着 27MB 内存，且数据可能已经变了。
typedef LanSyncBackupSource = Future<LanSyncBackup> Function();
