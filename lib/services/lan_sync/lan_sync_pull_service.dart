/// 从局域网设备拉取数据：合并进来，或者整体替换。
///
/// **两种模式的区别只有最后一步**：握手、快照本机设置、下载、回写设置、记录
/// 状态全都一样；区别在于下载到的字节交给
/// `BackupMergeService`（合并）还是 `BackupImporter`（替换）。
///
/// **覆盖是破坏性的、合并不是**：前者会清空本机的词条与学习记录，后者一条
/// 都不删。确认门槛因此不同（见界面层的两种对话框）。
///
/// **为什么不在服务里失效界面缓存**：`invalidateLocalData` 需要 `WidgetRef`，
/// 属于界面的一次动作；两条模式都一样，由调用方在返回后做。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/backup/backup_bytes.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';

/// 一次拉取的结果。
///
/// 两条模式的字段含义一致（都回答「这次往本机写了多少东西」），
/// 只是覆盖模式下的 `updatedWords` 恒为 0——它没有"更新"这个概念。
class LanSyncPullResult {
  /// 以各字段构造。
  const new({
    required this.mode,
    required this.addedWords,
    required this.updatedWords,
    required this.addedLogs,
    required this.writtenRows,
    required this.wordCount,
  });

  /// 本次用的模式。
  final LanSyncPullMode mode;

  /// 新增的词条数。
  final int addedWords;

  /// 被对端更新的词条数（仅合并模式非零）。
  final int updatedWords;

  /// 新增的作答条数。
  final int addedLogs;

  /// 本次写进库的行数（覆盖模式下是整份备份的行数）。
  final int writtenRows;

  /// 完成后本机的词条总数。
  final int wordCount;
}

/// 局域网拉取服务。
class LanSyncPullService {
  /// 以客户端工厂、发现器、导入器、合并器与状态存储构造。
  new(
    this._clientFactory,
    this._discovery,
    this._importer,
    this._merger,
    this._states,
  );

  final LanSyncClientFactory _clientFactory;
  final LanSyncDiscovery _discovery;
  final BackupImporter _importer;
  final BackupMergeService _merger;
  final LanSyncStateStore _states;

  /// 搜索同网段的共享设备。
  ///
  /// [excludeInstanceId] 是本机当前共享会话的标识：同一台设备既开着共享、
  /// 又点了「搜索设备」时会收到自己的应答，按会话标识剔除是精确的
  /// （按地址比对会漏掉多网卡与多网段的情况）。
  Future<LanSyncDiscoveryResult> discover({String? excludeInstanceId}) async {
    final result = await _discovery.discover(
      timeout: const Duration(milliseconds: lanSyncDiscoveryTimeoutMs),
    );
    if (excludeInstanceId == null || excludeInstanceId.isEmpty) return result;
    return LanSyncDiscoveryResult(
      hosts: result.hosts
          .where((host) => host.instanceId != excludeInstanceId)
          .toList(growable: false),
      incompatibleHostCount: result.incompatibleHostCount,
    );
  }

  /// 拉取指定设备的数据，按 [mode] 合并或替换。
  ///
  /// 顺序不能调换：**先握手验码，再取快照，最后才下载**——错码的代价应当是
  /// 一次几百字节的请求，而不是一次 27MB 的传输。
  Future<LanSyncPullResult> pull({
    required DiscoveredLanHost host,
    required String pairingCode,
    required LanSyncPullMode mode,
  }) async {
    try {
      final client = _clientFactory(host, pairingCode);
      final handshake = await client.handshake();
      // 快照必须在写入**之前**取：写入会整份替换设置表，之后再取就晚了。
      final snapshot = await _states.snapshot();
      final backup = await client.downloadBackup();
      final raw = decodeBackupUtf8(backup.bytes);
      final result = switch (mode) {
        LanSyncPullMode.merge => await _merge(raw),
        LanSyncPullMode.replace => await _replace(raw),
      };
      await _states.restore(snapshot);
      await _states.recordSuccess(peer: _peerLabel(host, handshake.deviceName));
      return result;
    } on AppError catch (error) {
      await _states.recordFailure(error.code.code);
      rethrow;
    }
  }

  /// 合并路径。
  Future<LanSyncPullResult> _merge(String raw) async {
    final outcome = await _merger.merge(raw);
    final counts = outcome.counts;
    return LanSyncPullResult(
      mode: LanSyncPullMode.merge,
      addedWords: counts.addedWords,
      updatedWords: counts.updatedWords,
      addedLogs: counts.addedLogs,
      writtenRows: counts.addedWords + counts.addedLogs + counts.addedSessions,
      wordCount: outcome.tables['words']?.length ?? 0,
    );
  }

  /// 覆盖路径（与 v1 完全相同）。
  Future<LanSyncPullResult> _replace(String raw) async {
    final imported = await _importer.import(raw);
    final words = imported.rowCounts['words'] ?? 0;
    return LanSyncPullResult(
      mode: LanSyncPullMode.replace,
      addedWords: words,
      updatedWords: 0,
      addedLogs: imported.rowCounts['review_logs'] ?? 0,
      writtenRows: imported.totalRows,
      wordCount: words,
    );
  }

  /// 状态行里的对端标签。
  ///
  /// 优先用握手带回来的设备名：发现列表里的名字可能是空串（对方还没命名），
  /// 而握手那一份是同一台设备在同一个响应里给出的、更权威的展示名。
  String _peerLabel(DiscoveredLanHost host, String handshakeName) =>
      handshakeName.isEmpty ? host.label : '$handshakeName（${host.address}）';
}
