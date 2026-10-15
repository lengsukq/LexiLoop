/// 原生端（macOS / Android）的数据库连接。
///
/// 由 `database_connection.dart` 条件导入选中。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:lexiloop/data/db/database.dart' show databaseFileName;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 打开应用支持目录下的 SQLite 文件。
///
/// 用 `LazyDatabase` 是因为应用支持目录的解析是异步的，
/// 而 Drift 的连接构造是同步的。
///
/// `createInBackground` 把 SQLite 放到独立 isolate：扫描 27 MB 备份、
/// 重算 `word_review_stats` 这类长查询不会卡住 UI 线程。
QueryExecutor openAppDatabaseExecutor() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, databaseFileName));
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
}
