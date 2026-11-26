/// 数据库的 Riverpod 提供者。
///
/// 数据库在整个应用生命周期内单例存在：`AppDatabase` 内部持有连接与
/// 查询缓存，反复开关会丢失事务语义并显著拖慢启动。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/database.dart';

/// 全局唯一的数据库实例。
///
/// 在 provider 释放时关闭连接，避免测试间互相污染。
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});
