/// 备份大小的人类可读格式。
///
/// **为什么不用现成的格式化库**：备份文件通常落在 KB–MB，四级阶梯之内就够，
/// 不必为一次提示引入一个依赖。抽成独立文件是因为本地导出、远端上传与
/// 远端列表三处都要显示同一个口径的大小。
library;

/// 备份字节数的展示单位。
const List<String> backupByteUnits = <String>['B', 'KB', 'MB', 'GB'];

/// 把字节数写成人类可读的大小，例如 `27.1 MB`。
String formatBackupBytes(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < backupByteUnits.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${backupByteUnits[unit]}';
}
