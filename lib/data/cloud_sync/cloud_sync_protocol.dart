/// Next.js 云端跨端同步的 HTTP 线上契约与响应解析。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/cloud_sync_progress.dart';
import 'package:lexiloop/domain/sync/delta_batch_splitter.dart';

/// 握手路径：验密码、协商协议与交换水位线。
const String cloudSyncHandshakePath = '/api/sync/handshake';

/// 分页拉取路径（支持增量与覆盖两种模式）。
const String cloudSyncPullPath = '/api/sync/pull';

/// 分批推送路径（服务端单事务增量合并与 FSRS 重放）。
const String cloudSyncPushPath = '/api/sync/push';

/// 握手请求体。
class CloudSyncHandshakeRequest {
  /// 以本机设备身份与已知服务端纪元构造。
  const new({
    required this.deviceId,
    required this.deviceName,
    required this.datasetEpoch,
    this.knownServerEpoch = '',
  });

  /// 本机持久化设备 ID。
  final String deviceId;

  /// 本机展示名。
  final String deviceName;

  /// 本机当前数据集纪元。
  final String datasetEpoch;

  /// 本机上次记录的服务端纪元。
  final String knownServerEpoch;

  /// 编码为 JSON 映射。
  Map<String, Object?> toJson() => <String, Object?>{
    'protocolVersion': cloudSyncProtocolVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'datasetEpoch': datasetEpoch,
    'knownServerEpoch': knownServerEpoch,
  };
}

/// 握手成功响应。
class CloudSyncHandshakeReply {
  /// 以服务端身份、时间、词条数与推送水位构造。
  const new({
    required this.deviceId,
    required this.datasetEpoch,
    required this.serverNow,
    required this.wordCount,
    this.pushSince,
  });

  /// 服务端持久化设备 ID。
  final String deviceId;

  /// 服务端当前数据集纪元。
  final String datasetEpoch;

  /// 服务端当前时间戳（epoch 毫秒）。
  final int serverNow;

  /// 服务端当前词条总数。
  final int wordCount;

  /// 服务端建议客户端推送的起始水位（全量时为 `null`）。
  final int? pushSince;
}

/// 分页拉取请求体。
class CloudSyncPullRequest {
  /// 以拉取模式、水位线、快照时刻、游标与页预算构造。
  const new({
    required this.mode,
    this.since,
    this.snapshotAt,
    this.cursor,
    this.maxPageBytes = cloudSyncMaxPullPageBytes,
  });

  /// `delta` 或 `replace`。
  final String mode;

  /// 增量拉取起始水位；全量时为 `null`。
  final int? since;

  /// 首页返回的快照时刻，用于后续分页保持窗口一致。
  final int? snapshotAt;

  /// 上一页返回的续传游标。
  final Map<String, Object?>? cursor;

  /// 单页原始 JSON 字节预算。
  final int maxPageBytes;

  /// 编码为 JSON 映射。
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode,
    if (since != null) 'since': since,
    if (snapshotAt != null) 'snapshotAt': snapshotAt,
    if (cursor != null) 'cursor': cursor,
    'maxPageBytes': maxPageBytes,
  };
}

/// 拉取单页的分页元信息。
class CloudSyncPullMeta {
  /// 以快照时钟、纪元、是否还有下一页与游标构造。
  const new({
    required this.serverNow,
    required this.snapshotAt,
    required this.datasetEpoch,
    required this.hasMore,
    this.nextCursor,
  });

  /// 服务端导出时刻。
  final int serverNow;

  /// 本轮分页固定的快照时刻。
  final int snapshotAt;

  /// 服务端数据集纪元。
  final String datasetEpoch;

  /// 是否还有后续页。
  final bool hasMore;

  /// 下一页续传游标；末页为 `null`。
  final Map<String, Object?>? nextCursor;
}

/// 拉取单页数据。
class CloudSyncPullPage {
  /// 以元信息、表行、词条引用、网络字节与是否增量构造。
  const new({
    required this.meta,
    required this.tables,
    required this.wordRefs,
    required this.wireBytes,
    required this.isIncremental,
  });

  /// 分页元信息。
  final CloudSyncPullMeta meta;

  /// 本页包含的各表行数据。
  final Map<String, List<Map<String, Object?>>> tables;

  /// 本页子表引用但未在本页 `words` 中的老词身份映射。
  final List<Map<String, Object?>> wordRefs;

  /// 本次响应网络字节数。
  final int wireBytes;

  /// 本页是否基于水位线的增量切片。
  final bool isIncremental;
}

/// 推送批次附带的客户端元信息。
class CloudSyncPushMeta {
  /// 以客户端身份与双侧水位时间戳构造。
  const new({
    required this.clientDeviceId,
    required this.clientDeviceName,
    required this.clientDatasetEpoch,
    required this.clientServerNow,
    this.pulledServerNow = 0,
  });

  /// 客户端持久化设备 ID。
  final String clientDeviceId;

  /// 客户端展示名。
  final String clientDeviceName;

  /// 客户端当前数据集纪元。
  final String clientDatasetEpoch;

  /// 客户端本轮导出时刻。
  final int clientServerNow;

  /// 客户端本轮从服务端拉取到的快照时刻。
  final int pulledServerNow;
}

/// 分批推送请求体。
class CloudSyncPushRequest {
  /// 以增量分片、客户端元信息及是否提交水位构造。
  const new({
    required this.batch,
    required this.meta,
    required this.commitWatermark,
  });

  /// 待推送的自包含增量分片。
  final CloudSyncPushBatch batch;

  /// 客户端身份与水位信息。
  final CloudSyncPushMeta meta;

  /// 仅在最后一批置为 `true`，通知服务端落盘水位线。
  final bool commitWatermark;

  /// 编码为 `/api/sync/push` 请求 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
    'format': lanSyncDeltaFormat,
    'version': lanSyncDeltaVersion,
    'clientDeviceId': meta.clientDeviceId,
    'clientDeviceName': meta.clientDeviceName,
    'clientDatasetEpoch': meta.clientDatasetEpoch,
    'clientServerNow': meta.clientServerNow,
    'pulledServerNow': meta.pulledServerNow,
    'commitWatermark': commitWatermark,
    'word_refs': batch.wordRefs,
    'session_refs': batch.sessionRefs,
    'item_refs': batch.itemRefs,
    for (final entry in batch.tables.entries) entry.key: entry.value,
  };
}

/// 单批推送响应。
class CloudSyncPushReply {
  /// 以合并摘要、服务端最新纪元、时钟与传输字节构造。
  const new({
    required this.summary,
    required this.datasetEpoch,
    required this.serverNow,
    required this.wireBytes,
  });

  /// 服务端本批合入统计。
  final CloudSyncSideCounts summary;

  /// 服务端最新数据集纪元。
  final String datasetEpoch;

  /// 服务端写入完成时间戳。
  final int serverNow;

  /// 本批上传的网络压缩字节数。
  final int wireBytes;
}

/// 解析 Next.js 统一信封 `{ success: true, data: ... }` 中的 `data` 映射。
Map<String, Object?> unwrapCloudSyncData(Map<String, Object?> envelope) {
  if (envelope['success'] != true || envelope['data'] is! Map) {
    throw const ValidationError(AppErrorCode.cloudSyncRequestFailed);
  }
  return _toStringMap(envelope['data']! as Map<Object?, Object?>);
}

/// 提取 Next.js 失败信封里的业务错误码（若有）。
String? extractCloudSyncErrorCode(Map<String, Object?>? envelope) {
  final err = envelope?['error'];
  if (err is! Map) return null;
  final code = err['code'];
  return code is String && code.isNotEmpty ? code : null;
}

/// 解析握手响应的 `data` 对象。
CloudSyncHandshakeReply parseCloudSyncHandshakeReply(
  Map<String, Object?> data,
) {
  if (data['service'] != cloudSyncServiceName) {
    throw const ExternalServiceError(AppErrorCode.cloudSyncRequestFailed);
  }
  final version = _intOf(data['protocolVersion']);
  if (version != cloudSyncProtocolVersion) {
    throw const ExternalServiceError(AppErrorCode.cloudSyncProtocolMismatch);
  }
  final pushSince = _intOf(data['pushSince']);
  return CloudSyncHandshakeReply(
    deviceId: _str(data['deviceId']),
    datasetEpoch: _str(data['datasetEpoch']),
    serverNow: _intOf(data['serverNow']) ?? 0,
    wordCount: _intOf(data['wordCount']) ?? 0,
    pushSince: pushSince != null && pushSince > 0 ? pushSince : null,
  );
}

/// 解析分页拉取响应的 `data` 对象。
CloudSyncPullPage parseCloudSyncPullPage(
  Map<String, Object?> data, {
  required int wireBytes,
}) {
  final rawTables = data['tables'];
  if (rawTables is! Map) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  final tables = <String, List<Map<String, Object?>>>{};
  for (final entry in rawTables.entries) {
    if (entry.key is! String) continue;
    tables[entry.key! as String] = _parseRowList(entry.value);
  }
  final rawCursor = data['nextCursor'];
  return CloudSyncPullPage(
    meta: CloudSyncPullMeta(
      serverNow: _intOf(data['serverNow']) ?? 0,
      snapshotAt: _intOf(data['snapshotAt']) ?? 0,
      datasetEpoch: _str(data['datasetEpoch']),
      hasMore: data['hasMore'] == true,
      nextCursor: rawCursor is Map
          ? _toStringMap(rawCursor as Map<Object?, Object?>)
          : null,
    ),
    tables: tables,
    wordRefs: _parseRowList(data['word_refs']),
    wireBytes: wireBytes,
    isIncremental: data['isIncremental'] == true,
  );
}

/// 解析分批推送响应的 `data` 对象。
CloudSyncPushReply parseCloudSyncPushReply(
  Map<String, Object?> data, {
  required int wireBytes,
}) {
  final rawSummary = data['summary'];
  final summaryMap = rawSummary is Map
      ? _toStringMap(rawSummary as Map<Object?, Object?>)
      : const <String, Object?>{};
  return CloudSyncPushReply(
    summary: CloudSyncSideCounts(
      addedWords: _intOf(summaryMap['addedWords']) ?? 0,
      updatedWords: _intOf(summaryMap['updatedWords']) ?? 0,
      addedLogs: _intOf(summaryMap['addedLogs']) ?? 0,
      rebuiltWords: _intOf(summaryMap['rebuiltWords']) ?? 0,
      wordCount: _intOf(summaryMap['wordCount']) ?? 0,
    ),
    datasetEpoch: _str(data['datasetEpoch']),
    serverNow: _intOf(data['serverNow']) ?? 0,
    wireBytes: wireBytes,
  );
}

List<Map<String, Object?>> _parseRowList(Object? raw) {
  if (raw == null) return const <Map<String, Object?>>[];
  if (raw is! List) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  final rows = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    rows.add(_toStringMap(item as Map<Object?, Object?>));
  }
  return rows;
}

Map<String, Object?> _toStringMap(Map<Object?, Object?> raw) =>
    <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };

String _str(Object? value) => value is String ? value.trim() : '';

int? _intOf(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
