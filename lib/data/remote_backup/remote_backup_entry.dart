/// 远端备份目录里的一项。
///
/// 只有「选一份来恢复」需要的三个字段：文件名、大小、修改时间。
/// **不建模 ETag**：本版不做条件请求与冲突检测，多一个读了不用的字段
/// 只会让解析层看起来比实际能力更强。
library;

/// 远端备份条目。
class RemoteBackupEntry {
  /// 以文件名、字节数与修改时间构造。
  const new({required this.name, required this.sizeBytes, this.modifiedAt});

  /// 文件名（不含目录），例如 `lexiloop-backup-2026-10-16-101500.json`。
  final String name;

  /// 字节数；服务器没给 `getcontentlength` 时为 0。
  final int sizeBytes;

  /// 修改时间（UTC）；服务器没给 `getlastmodified` 时为 `null`。
  final DateTime? modifiedAt;
}
