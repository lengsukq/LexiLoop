/// 局域网同步的本机设置与上次同步状态。
///
/// 与 `WebdavStateStore` 同一套约定：把「读设置、改一两个状态字段、写回」
/// 收在一个入口，避免三条链路（开共享 / 搜索 / 拉取）各写一遍，
/// 其中某一条忘了保留别的字段。
///
/// **读-改-写以解析后的设置为基准**：与 WebDAV 不同，这里的值里没有
/// 「半填的凭据」这种中间态（配对码不落盘，见模型文件的说明），
/// 因此可以直接用 [LanSyncSettings] 合并，不必再拿一份原始映射。
library;

import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 局域网同步设置的读写入口。
class LanSyncStateStore {
  /// 以设置服务与时钟构造。
  ///
  /// `clock` 是「上次成功时间」的可测性接缝：默认读系统时钟。
  new(this._settings, {int Function()? clock}) : _clock = clock ?? _wallClockMs;

  final SettingsService _settings;
  final int Function() _clock;

  /// 读取当前设置（含按平台推导的兜底设备名）。
  Future<LanSyncSettings> load() async => lanSyncSettingsFromRaw(
    (await _settings.load()).raw[lanSyncSettingsKey],
    fallbackDeviceName: defaultLanSyncDeviceName(
      isDesktop: PlatformCaps.isDesktop,
    ),
  );

  /// 覆盖设备名。
  ///
  /// 传空串表示「回到平台默认名」：落盘时该字段会被省略，
  /// 下次 [load] 又会填回兜底名。
  Future<void> setDeviceName(String name) =>
      _write((current) => current.copyWith(deviceName: name.trim()));

  /// 覆盖监听端口。
  Future<void> setPort(int port) =>
      _write((current) => current.copyWith(port: port));

  /// 覆盖拉取时的合并方式。
  Future<void> setPullMode(LanSyncPullMode mode) =>
      _write((current) => current.copyWith(pullMode: mode));

  /// 记录一次成功拉取。
  ///
  /// 同时清掉上次的失败原因：状态行若还挂着「上次失败」，
  /// 用户会以为最新的那次也失败了。
  Future<void> recordSuccess({required String peer}) => _write(
    (current) => current.copyWith(
      lastSuccessAt: _clock(),
      lastPeer: peer,
      clearError: true,
    ),
  );

  /// 记录一次失败（保留上次成功与它的对端标签）。
  ///
  /// **只存错误码、不存文案**：文案由 `AppErrorCode.defaultMessage` 唯一决定，
  /// 存进设置表会让改了文案的版本读回旧句子。
  Future<void> recordFailure(String code) =>
      _write((current) => current.copyWith(lastError: code));

  /// 取一份本机设置的快照，供全量替换之后写回。
  ///
  /// **为什么需要它**：拉取会走 `BackupImporter.import`，那条路径会整份替换
  /// `settings` 表——于是本机的设备名与端口会被主机的覆盖，两台设备变成同名，
  /// 发现列表里再也分不清谁是谁。快照 + [restore] 是这条链路唯一的补丁。
  Future<Map<String, Object?>> snapshot() async => (await load()).toStorage();

  /// 把一份快照写回设置表。
  ///
  /// **先失效缓存再写**：`SettingsService` 内部缓存了整个设置表，而
  /// `BackupImporter` 是绕过它直接写库的。若不先失效，这里的读-改-写会以
  /// 导入前的陈旧快照为基准，把别的键一起写回去。
  Future<void> restore(Map<String, Object?> snapshot) async {
    _settings.invalidate();
    await _settings.update(<String, Object?>{
      lanSyncSettingsKey: snapshot.isEmpty ? null : snapshot,
    }, now: _clock());
  }

  /// 读取-改-写。
  Future<void> _write(LanSyncSettings Function(LanSyncSettings) change) async {
    final updated = change(await load());
    await _settings.update(<String, Object?>{
      lanSyncSettingsKey: updated.toStorage(),
    }, now: _clock());
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
