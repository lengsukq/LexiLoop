/// Web 端的数据库连接：drift 的 WASM 实现 + 浏览器持久化存储。
///
/// 由 `database_connection.dart` 条件导入选中。
///
/// **为什么不用 `@DriftDatabase(web:)`**：解析到的 drift 2.35.2 并没有
/// `DriftWebOptions`，那条注解式写法在这个版本上不存在；只能用
/// `WasmDatabase.open()` 手工装配执行器。
library;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// 浏览器存储里数据库的名字。
///
/// 与原生端文件名（`lexiloop.sqlite`）不同名是有意的：浏览器里
/// IndexedDB / OPFS 的条目名不带扩展名，drift 官方示例同样如此。
const String webDatabaseName = 'lexiloop';

/// `sqlite3.wasm` 与 drift worker 脚本的相对路径。
///
/// 相对 URI 会按当前页面地址解析，因此 `flutter run -d chrome` 与部署到
/// 子路径的构建都能命中 `web/` 下的同名文件。
const String _sqlite3WasmPath = 'sqlite3.wasm';
const String _driftWorkerPath = 'drift_worker.js';

/// 打开浏览器内的 SQLite 数据库。
///
/// 用 `DatabaseConnection.delayed` 包住异步打开过程，让 `AppDatabase`
/// 的构造保持同步——与原生端的 `LazyDatabase` 是同一套语义。
QueryExecutor openAppDatabaseExecutor() {
  return DatabaseConnection.delayed(
    Future<DatabaseConnection>(() async {
      final result = await WasmDatabase.open(
        databaseName: webDatabaseName,
        sqlite3Uri: Uri.parse(_sqlite3WasmPath),
        driftWorkerUri: Uri.parse(_driftWorkerPath),
      );
      return result.resolvedExecutor;
    }),
  );
}
