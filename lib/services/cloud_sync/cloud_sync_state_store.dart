/// Next.js 云端同步本机配置、水位线与覆盖恢复保护的存储层。
library;

import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 覆盖恢复前需要保护的本机专属配置快照（避免云端覆盖抹掉本机凭据与身份）。
class CloudSyncLocalSettingsSnapshot {
  /// 以云端同步、局域网与 WebDAV 原始配置映射构造。
  const new({
    required this.cloudSync,
    required this.lanSync,
    required this.webdav,
  });

  /// 本机 `cloudSync` 原始值。
  final Object? cloudSync;

  /// 本机 `lanSync` 原始值。
  final Object? lanSync;

  /// 本机 `webdavBackup` 原始值。
  final Object? webdav;
}

/// 云端同步状态读写封装。
class CloudSyncStateStore {
  /// 以设置服务与可选时钟构造。
  new(this._settings, {int Function()? clock}) : _clock = clock ?? _wallClockMs;

  final SettingsService _settings;
  final int Function() _clock;

  /// 读取当前云端同步设置。
  Future<CloudSyncSettings> load() async =>
      cloudSyncSettingsFromRaw((await _settings.load()).raw[cloudSyncKey]);

  /// 更新服务器地址或密码；地址变更时自动清空旧服务器水位线。
  Future<void> saveCredential({
    required String baseUrl,
    required String password,
  }) => _write((current) {
    final trimmedUrl = baseUrl.trim();
    final sameHost =
        normalizeCloudSyncBaseUrl(current.credential?.baseUrl ?? '') ==
        normalizeCloudSyncBaseUrl(trimmedUrl);
    final nextCredential = trimmedUrl.isEmpty
        ? null
        : CloudSyncCredential(baseUrl: trimmedUrl, password: password);
    return CloudSyncSettings(
      credential: nextCredential,
      mode: current.mode,
      status: current.status,
      watermark: sameHost ? current.watermark : null,
    );
  });

  /// 更新默认同步模式。
  Future<void> setMode(CloudSyncMode mode) =>
      _write((current) => current.copyWith(mode: mode));

  /// 记录一次同步成功、服务端词条数、摘要与最新水位线。
  Future<void> recordSuccess({
    required CloudSyncWatermark watermark,
    required int serverWordCount,
    required String summary,
  }) => _write(
    (current) => current.copyWith(
      watermark: watermark,
      status: CloudSyncLastStatus(
        lastSuccessAt: _clock(),
        lastServerWordCount: serverWordCount,
        lastSummary: summary,
      ),
    ),
  );

  /// 记录一次失败错误码（保留上次成功时间与水位线）。
  Future<void> recordFailure(String errorCode) => _write(
    (current) => current.copyWith(
      status: CloudSyncLastStatus(
        lastSuccessAt: current.status.lastSuccessAt,
        lastError: errorCode,
        lastServerWordCount: current.status.lastServerWordCount,
        lastSummary: current.status.lastSummary,
      ),
    ),
  );

  /// 拍摄覆盖恢复前需保留的本机配置快照。
  Future<CloudSyncLocalSettingsSnapshot> snapshotLocalSecrets() async {
    final raw = (await _settings.load()).raw;
    return CloudSyncLocalSettingsSnapshot(
      cloudSync: raw[cloudSyncKey],
      lanSync: raw['lanSync'],
      webdav: raw[webdavSettingsKey],
    );
  }

  /// 覆盖恢复后写回本机云端同步与 WebDAV 配置（`lanSync` 由 `LanSyncStateStore` 单独轮换）。
  Future<void> restoreAfterReplace(
    CloudSyncLocalSettingsSnapshot snapshot,
  ) async {
    _settings.invalidate();
    await _settings.update(<String, Object?>{
      cloudSyncKey: snapshot.cloudSync,
      webdavSettingsKey: snapshot.webdav,
    }, now: _clock());
  }

  Future<void> _write(
    CloudSyncSettings Function(CloudSyncSettings) change,
  ) async {
    final updated = change(await load());
    final stored = updated.toStorage();
    await _settings.update(<String, Object?>{
      cloudSyncKey: stored.isEmpty ? null : stored,
    }, now: _clock());
  }
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
