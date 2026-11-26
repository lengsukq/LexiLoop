/// 设置的读取与缓存。
///
/// 对应旧版 `modules/settings/service.ts`。旧版有 30 秒 TTL 缓存；
/// 本地单进程下改成「显式失效」——设置只在设置页被改动，
/// 用时间窗缓存反而会让用户改完看不到效果。
library;

import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 设置读取入口。
class SettingsService {
  /// 以 DAO 构造。
  new(this._dao);

  final SettingsDao _dao;

  AppSettings? _cached;

  /// 读取当前设置（首次读取后缓存）。
  Future<AppSettings> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final settings = appSettingsFromRaw(await _dao.loadRaw());
    _cached = settings;
    return settings;
  }

  /// 覆盖写入若干设置项并刷新缓存。
  ///
  /// 传 `null` 表示「删除该键，回到默认值」。
  Future<AppSettings> update(
    Map<String, Object?> changes, {
    required int now,
  }) async {
    final current = await load();
    final merged = <String, Object?>{...current.raw};
    final effective = <String, Object?>{};
    // 值为 `null` 表示「删除该键、回到默认值」。删除必须落到表上：
    // 只从内存的 merged 里去掉的话，缓存一失效（或应用重启）旧值就回来了。
    final removed = <String>[];

    for (final entry in changes.entries) {
      if (entry.value == null) {
        merged.remove(entry.key);
        removed.add(entry.key);
      } else {
        merged[entry.key] = entry.value;
        effective[entry.key] = entry.value;
      }
    }

    await _dao.saveAll(effective, now, removedKeys: removed);
    _cached = appSettingsFromRaw(merged);
    return _cached!;
  }

  /// 丢弃缓存，下次 [load] 重新读取。
  void invalidate() => _cached = null;
}
