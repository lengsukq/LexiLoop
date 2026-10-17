/// 备份文件名的唯一出处。
///
/// **为什么抽出来**：文件名同时出现在本地导出（分享面板/浏览器下载）与
/// 远程上传（WebDAV 的 PUT 目标）两处。各写一份的后果很具体——用户按
/// `lexiloop-backup-*` 在「文件」应用里找备份、在远端目录里筛备份，
/// 一旦两处格式漂移，筛不出来还找不到原因。
library;

import 'package:lexiloop/core/date_key.dart';

/// 导出文件名的固定前缀。
///
/// 让用户在「文件」应用里一眼认出这是备份，而不是某个临时文件；
/// 远端列表也用同一个前缀筛选「哪些文件是本应用产生的」。
const String backupFilePrefix = 'lexiloop-backup-';

/// 带时间戳的备份文件名，例如 `lexiloop-backup-2026-10-14-222752.json`。
///
/// 日期段走 `dateKey`，与旧版 `/api/backups/json` 的
/// `Content-Disposition` 用的是同一套 `YYYY-MM-DD`；前缀与时分秒是纯本地版
/// 新增的——旧版每次导出覆盖同名文件，本地版需要让多次导出能并排存放。
///
/// **两次导出落在同一秒会同名**：这是刻意保留的语义（“秒”是文件名的最小
/// 粒度），远端 PUT 会覆盖同名对象，也就是「同一秒的两次导出视为同一份」。
String backupFileName(DateTime now) =>
    '$backupFilePrefix${dateKey(now.millisecondsSinceEpoch)}'
    '-${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}.json';

/// 两位补零，让文件名里的时间字段能按字典序排序。
String _pad(int value) =>
    // 宽度就是「一位数字 + 补位」里的两位，没有语义可命名。
    value.toString().padLeft(2, '0'); // guard:allow-magic
