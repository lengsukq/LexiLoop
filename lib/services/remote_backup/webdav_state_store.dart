/// 远程备份的共享状态读写。
///
/// 三个服务（上传 / 恢复 / 自动备份）都要做同一件事：把「上次成功、上次失败、
/// 上次上传时的数据检查点」写回 `settings.raw['webdavBackup']`。各写一遍的下场
/// 很具体——某一条路径忘了保留凭据，用户的密码就被抹掉了。
///
/// **读-改-写**：`WebdavBackupState` 的字段来自当前设置，写回时只覆盖状态字段，
/// 凭据原样带回（`_write` 内部先 `load()` 再合并）。
library;

import 'package:lexiloop/data/db/daos/backup_checkpoint_dao.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 远程备份状态的读写入口。
class WebdavStateStore {
  /// 以设置服务与时钟构造。
  ///
  /// `clock` 是「上次成功时间」的可测性接缝：默认读系统时钟。
  new(this._settings, {int Function()? clock}) : _clock = clock ?? _wallClockMs;

  final SettingsService _settings;
  final int Function() _clock;

  /// 读取当前远程备份设置（含凭据）。
  Future<WebdavSettings> load() async =>
      webdavSettingsFromRaw((await _settings.load()).raw[webdavSettingsKey]);

  /// 记录一次成功上传。
  ///
  /// 同时清掉上次的失败原因：状态行若还挂着「上次失败」，
  /// 用户会以为最新的那次也失败了。
  Future<void> recordSuccess(DataCheckpoint checkpoint) => _write(
    (state) => state.copyWith(
      lastSuccessAt: _clock(),
      lastCheckpoint: checkpointWire(checkpoint),
      clearError: true,
    ),
  );

  /// 记录一次失败（保留上次成功与该次成功时的检查点）。
  ///
  /// **只存错误码，不存文案**：文案由 `AppErrorCode.defaultMessage` 唯一决定，
  /// 存进设置表会让改了文案的版本读回旧句子。
  Future<void> recordFailure(String code) =>
      _write((state) => state.copyWith(lastError: code));

  /// 覆盖自动备份周期。
  Future<void> setAutoInterval(int minutes) =>
      _write((state) => state.copyWith(autoIntervalMinutes: minutes));

  /// 覆盖状态字段；凭据保持不动。
  Future<void> _write(
    WebdavBackupState Function(WebdavBackupState) change,
  ) async {
    final current = await load();
    final updated = WebdavSettings(
      credential: current.credential,
      state: change(current.state),
    );
    // **凭据字段取自存储里的原始值**，不是解析后的 `WebdavCredential`：
    // 用户可能刚填了地址与账号、还没填密码（此时解析结果是 null），
    // 用它回写会把那两栏抹掉。状态字段则用合并后的新值。
    final merged = webdavStorageFromFields(
      credential: await _rawMap(),
      state: updated.state,
    );
    await _settings.update(<String, Object?>{
      webdavSettingsKey: merged.isEmpty ? null : merged,
    }, now: _clock());
  }

  /// 存储里的原始映射。
  Future<Map<String, Object?>> _rawMap() async {
    final raw = (await _settings.load()).raw[webdavSettingsKey];
    if (raw is! Map) return <String, Object?>{};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
