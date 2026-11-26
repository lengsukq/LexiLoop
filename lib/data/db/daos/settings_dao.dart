/// 设置的读写。
///
/// `settings` 表是 key → value_json 的键值表。DAO 只负责
/// 「键值 ↔ JSON」，类型化语义在 `domain/models/app_settings.dart`。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/database.dart';

/// 设置读写入口。
class SettingsDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 读取全部设置为原始键值映射。
  ///
  /// 单个键的 JSON 损坏时**跳过该键**而不是整表失败——设置项彼此独立，
  /// 一个坏值不该让应用退回全默认。
  Future<Map<String, Object?>> loadRaw() async {
    final rows = await _db.select(_db.settings).get();
    final result = <String, Object?>{};
    for (final row in rows) {
      final decoded = _decodeValue(row.valueJson);
      if (decoded != null) result[row.key] = decoded;
    }
    return result;
  }

  /// 写入若干设置项；[removedKeys] 里的键从表中删除。
  ///
  /// 删除与写入放在同一个 batch 里：设置页的「恢复默认」是一次原子操作，
  /// 拆成两次调用会在中途失败时留下一半旧值一半默认值。
  Future<void> saveAll(
    Map<String, Object?> values,
    int now, {
    List<String> removedKeys = const <String>[],
  }) async {
    if (values.isEmpty && removedKeys.isEmpty) return;
    await _db.batch((batch) {
      for (final key in removedKeys) {
        batch.deleteWhere(_db.settings, (_) => _db.settings.key.equals(key));
      }
      for (final entry in values.entries) {
        batch.insert(
          _db.settings,
          SettingsCompanion.insert(
            key: entry.key,
            valueJson: jsonEncode(entry.value),
            updatedAt: now,
          ),
          onConflict: DoUpdate(
            (_) => SettingsCompanion(
              valueJson: Value(jsonEncode(entry.value)),
              updatedAt: Value(now),
            ),
            target: <Column<Object>>[_db.settings.key],
          ),
        );
      }
    });
  }

  /// 解析单个设置值；空值与非法 JSON 返回 `null`。
  Object? _decodeValue(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}
