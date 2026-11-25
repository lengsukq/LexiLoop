/// 局域网同步的本机设置、持久化设备身份与增量水位线存储。
library;

import 'dart:math';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 局域网同步设置的读写入口。
class LanSyncStateStore {
  /// 以设置服务、可选时钟与可选随机串生成器构造。
  new(
    this._settings, {
    int Function()? clock,
    String Function(int length)? tokenGenerator,
  }) : _clock = clock ?? _wallClockMs,
       _generateToken = tokenGenerator ?? _secureHexToken;

  final SettingsService _settings;
  final int Function() _clock;
  final String Function(int length) _generateToken;

  /// 读取当前设置（含按平台推导的兜底设备名）。
  Future<LanSyncSettings> load() async => lanSyncSettingsFromRaw(
    (await _settings.load()).raw[lanSyncSettingsKey],
    fallbackDeviceName: defaultLanSyncDeviceName(
      isDesktop: PlatformCaps.isDesktop,
    ),
  );

  /// 确保本机拥有持久化 `deviceId` 与 `datasetEpoch`；缺失时生成并落盘。
  Future<LanSyncSettings> ensureIdentity() async {
    final current = await load();
    if (current.identity.isReady) return current;
    final nextIdentity = LanSyncIdentity(
      deviceId: current.deviceId.isEmpty
          ? _generateToken(lanSyncDeviceIdLength)
          : current.deviceId,
      datasetEpoch: current.datasetEpoch.isEmpty
          ? _generateToken(lanSyncDatasetEpochLength)
          : current.datasetEpoch,
    );
    final updated = current.copyWith(identity: nextIdentity);
    await _save(updated);
    return updated;
  }

  /// 轮换本机 `datasetEpoch`（清空/覆盖恢复或 3+ 设备交叉合并时调用）。
  Future<LanSyncIdentity> rotateDatasetEpoch() async {
    final current = await ensureIdentity();
    final rotated = LanSyncIdentity(
      deviceId: current.deviceId,
      datasetEpoch: _generateToken(lanSyncDatasetEpochLength),
    );
    await _save(current.copyWith(identity: rotated));
    return rotated;
  }

  /// 覆盖设备名。
  Future<void> setDeviceName(String name) =>
      _write((current) => current.copyWith(deviceName: name.trim()));

  /// 覆盖监听端口。
  Future<void> setPort(int port) =>
      _write((current) => current.copyWith(port: port));

  /// 覆盖拉取/同步方式。
  Future<void> setPullMode(LanSyncPullMode mode) =>
      _write((current) => current.copyWith(pullMode: mode));

  /// 覆盖主机共享策略（双向合并 / 仅发送只读）。
  Future<void> setSharePolicy(LanSyncSharePolicy policy) =>
      _write((current) => current.copyWith(sharePolicy: policy));

  /// 记录一次成功拉取（清掉上次失败原因）。
  Future<void> recordSuccess({required String peer}) => _write(
    (current) => current.copyWith(
      lastSuccessAt: _clock(),
      lastPeer: peer,
      clearError: true,
    ),
  );

  /// 记录与某台对端同步完成后的最新水位线及状态。
  Future<void> recordPeerSync({
    required LanSyncPeerWatermark watermark,
    required String peerLabel,
  }) => _write((current) {
    final nextMap = Map<String, LanSyncPeerWatermark>.from(
      current.peerWatermarks,
    );
    if (watermark.peerDeviceId.isNotEmpty) {
      nextMap[watermark.peerDeviceId] = watermark;
    }
    return current.copyWith(
      lastSuccessAt: _clock(),
      lastPeer: peerLabel,
      clearError: true,
      peerWatermarks: nextMap,
    );
  });

  /// 记录一次失败（保留上次成功与对端标签）。
  Future<void> recordFailure(String code) =>
      _write((current) => current.copyWith(lastError: code));

  /// 取一份本机设置的快照，供覆盖恢复之后写回。
  Future<Map<String, Object?>> snapshot() async => (await load()).toStorage();

  /// 把一份快照写回设置表（先失效缓存再写）。
  Future<void> restore(Map<String, Object?> snapshot) async {
    _settings.invalidate();
    await _settings.update(<String, Object?>{
      lanSyncSettingsKey: snapshot.isEmpty ? null : snapshot,
    }, now: _clock());
  }

  /// 覆盖恢复后写回本机配置，同时轮换纪元并清空旧水位线，避免下次误走增量。
  Future<void> restoreAfterReplace(Map<String, Object?> snapshot) async {
    _settings.invalidate();
    final parsed = lanSyncSettingsFromRaw(
      snapshot,
      fallbackDeviceName: defaultLanSyncDeviceName(
        isDesktop: PlatformCaps.isDesktop,
      ),
    );
    final refreshed = parsed.copyWith(
      identity: LanSyncIdentity(
        deviceId: parsed.deviceId.isEmpty
            ? _generateToken(lanSyncDeviceIdLength)
            : parsed.deviceId,
        datasetEpoch: _generateToken(lanSyncDatasetEpochLength),
      ),
      peerWatermarks: const <String, LanSyncPeerWatermark>{},
    );
    await _save(refreshed);
  }

  Future<void> _write(LanSyncSettings Function(LanSyncSettings) change) async {
    final updated = change(await load());
    await _save(updated);
  }

  Future<void> _save(LanSyncSettings updated) => _settings.update(
    <String, Object?>{lanSyncSettingsKey: updated.toStorage()},
    now: _clock(),
  );
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;

String _secureHexToken(int length) {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i += 1) {
    buffer.write(
      lanSyncInstanceIdAlphabet[random.nextInt(
        lanSyncInstanceIdAlphabet.length,
      )],
    );
  }
  return buffer.toString();
}
