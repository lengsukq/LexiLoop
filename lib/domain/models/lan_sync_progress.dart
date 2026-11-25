/// 局域网同步的实时进度与双方状态快照模型（纯 Dart）。
///
/// 主机端与拉取端共用同一份状态模型驱动「双端词环共振桥」动画：
/// 无论作为发起方还是共享方，都能以本机为左节点、对端为右节点，
/// 如实映射连接、对账、发送、接收、合并与完成六个阶段。
library;

import 'package:lexiloop/core/constants.dart';

/// 局域网同步的生命周期阶段。
enum LanSyncPhase {
  /// 空闲，未在同步。
  idle,

  /// 主机已开启共享，等待同网段设备连接。
  waiting,

  /// 正在搜索同网段共享设备。
  discovering,

  /// 正在建立连接并校验配对码。
  connecting,

  /// 正在交换设备水位线、计算增量差异。
  diffing,

  /// 正在传输数据（双向或单向流光）。
  transferring,

  /// 正在本地增量落库与 FSRS 重放。
  merging,

  /// 同步完成，双端已收敛。
  completed,

  /// 同步失败或被中断。
  failed,
}

/// 本次同步相对「本机视角」的数据流动方向。
enum LanSyncDirection {
  /// 双向增量合并（本机 ⇄ 对端）。
  bidirectional,

  /// 仅拉取（对端 → 本机）。
  pullOnly,

  /// 仅发送（本机 → 对端；主机在对方只拉取时的视角）。
  pushOnly,
}

/// 同步链路的一端（本机或对端）展示信息。
class LanSyncEndpoint {
  /// 以设备名、设备类型与可选地址构造。
  const new({required this.name, required this.deviceKind, this.address = ''});

  /// 展示用的设备名。
  final String name;

  /// 设备类型（[lanSyncDeviceKindDesktop] 或 [lanSyncDeviceKindMobile]）。
  final String deviceKind;

  /// 可选的局域网地址文本（如 `192.168.1.8:8765`）。
  final String address;

  /// 是否桌面端设备。
  bool get isDesktop => deviceKind == lanSyncDeviceKindDesktop;
}

/// 传输阶段的字节进度与压缩统计。
class LanSyncByteMetrics {
  /// 以发送/接收字节统计构造。
  const new({
    this.sentBytes = 0,
    this.totalSendBytes = 0,
    this.receivedBytes = 0,
    this.totalReceiveBytes = 0,
    this.uncompressedBytes = 0,
  });

  /// 本机已发送的压缩字节数。
  final int sentBytes;

  /// 本机预计发送的压缩总字节数。
  final int totalSendBytes;

  /// 本机已接收的压缩字节数。
  final int receivedBytes;

  /// 本机预计接收的压缩总字节数。
  final int totalReceiveBytes;

  /// 传输载荷解压前的原始 JSON 总字节数（用于估算压缩节省比例）。
  final int uncompressedBytes;

  /// 发送进度（`0.0`–`1.0`）。
  double get uploadProgress => _ratio(sentBytes, totalSendBytes);

  /// 接收进度（`0.0`–`1.0`）。
  double get downloadProgress => _ratio(receivedBytes, totalReceiveBytes);

  /// 总传输字节数（发 + 收）。
  int get transferredWireBytes => sentBytes + receivedBytes;

  /// 预计总传输字节数（发 + 收）。
  int get totalWireBytes => totalSendBytes + totalReceiveBytes;

  /// 整体传输进度（`0.0`–`1.0`）。
  double get overallProgress => _ratio(transferredWireBytes, totalWireBytes);

  /// 覆盖若干字段。
  LanSyncByteMetrics copyWith({
    int? sentBytes,
    int? totalSendBytes,
    int? receivedBytes,
    int? totalReceiveBytes,
    int? uncompressedBytes,
  }) => LanSyncByteMetrics(
    sentBytes: sentBytes ?? this.sentBytes,
    totalSendBytes: totalSendBytes ?? this.totalSendBytes,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalReceiveBytes: totalReceiveBytes ?? this.totalReceiveBytes,
    uncompressedBytes: uncompressedBytes ?? this.uncompressedBytes,
  );
}

/// 单侧合并或替换结果的统计摘要。
class LanSyncDeltaSummary {
  /// 以各计数构造。
  const new({
    this.addedWords = 0,
    this.updatedWords = 0,
    this.addedLogs = 0,
    this.rebuiltWords = 0,
    this.wordCount = 0,
  });

  /// 从线上 JSON 解析；缺字段时按 0 处理。
  factory fromJson(Object? value) {
    if (value is! Map) return const LanSyncDeltaSummary();
    return LanSyncDeltaSummary(
      addedWords: _asInt(value['addedWords']),
      updatedWords: _asInt(value['updatedWords']),
      addedLogs: _asInt(value['addedLogs']),
      rebuiltWords: _asInt(value['rebuiltWords']),
      wordCount: _asInt(value['wordCount']),
    );
  }

  /// 新增词条数。
  final int addedWords;

  /// 更新元数据的词条数。
  final int updatedWords;

  /// 新增作答流水条数。
  final int addedLogs;

  /// 重新排期 FSRS 的词条数。
  final int rebuiltWords;

  /// 同步完成后该端的总词条数。
  final int wordCount;

  /// 本侧是否有任何实质变化。
  bool get hasChanges => addedWords > 0 || updatedWords > 0 || addedLogs > 0;

  /// 序列化为线上 JSON（用于在双端之间交换合并战果）。
  Map<String, Object?> toJson() => <String, Object?>{
    'addedWords': addedWords,
    'updatedWords': updatedWords,
    'addedLogs': addedLogs,
    'rebuiltWords': rebuiltWords,
    'wordCount': wordCount,
  };
}

/// 同步进度的详情负载（保持顶层构造参数精简）。
class LanSyncProgressDetail {
  /// 以增量标记、字节指标、双方摘要与错误码构造。
  const new({
    this.isIncremental = false,
    this.bytes = const LanSyncByteMetrics(),
    this.localSummary,
    this.peerSummary,
    this.errorCode,
  });

  /// 本次是否命中增量同步（`false` 表示首次全量或覆盖模式）。
  final bool isIncremental;

  /// 实时字节统计。
  final LanSyncByteMetrics bytes;

  /// 本机合并结果摘要（完成时非空）。
  final LanSyncDeltaSummary? localSummary;

  /// 对端合并结果摘要（双向完成时非空）。
  final LanSyncDeltaSummary? peerSummary;

  /// 失败时的业务错误码字符串。
  final String? errorCode;

  /// 覆盖若干字段。
  LanSyncProgressDetail copyWith({
    bool? isIncremental,
    LanSyncByteMetrics? bytes,
    LanSyncDeltaSummary? localSummary,
    LanSyncDeltaSummary? peerSummary,
    String? errorCode,
  }) => LanSyncProgressDetail(
    isIncremental: isIncremental ?? this.isIncremental,
    bytes: bytes ?? this.bytes,
    localSummary: localSummary ?? this.localSummary,
    peerSummary: peerSummary ?? this.peerSummary,
    errorCode: errorCode ?? this.errorCode,
  );
}

/// 一次同步过程某一时刻的完整状态快照。
class LanSyncTransferProgress {
  /// 以阶段、方向、本机信息、可选对端与详情构造。
  const new({
    required this.phase,
    required this.direction,
    required this.local,
    this.peer,
    this.detail = const LanSyncProgressDetail(),
  });

  /// 当前所处阶段。
  final LanSyncPhase phase;

  /// 本机视角的数据流方向。
  final LanSyncDirection direction;

  /// 本机设备信息。
  final LanSyncEndpoint local;

  /// 对端设备信息；等待连接前为 `null`。
  final LanSyncEndpoint? peer;

  /// 进度指标与摘要详情。
  final LanSyncProgressDetail detail;

  /// 是否正在活跃传输/处理中（动画应持续流转）。
  bool get isActive =>
      phase == LanSyncPhase.connecting ||
      phase == LanSyncPhase.diffing ||
      phase == LanSyncPhase.transferring ||
      phase == LanSyncPhase.merging;

  /// 是否已处于终态（完成或失败）。
  bool get isTerminal =>
      phase == LanSyncPhase.completed || phase == LanSyncPhase.failed;

  /// 覆盖若干字段。
  LanSyncTransferProgress copyWith({
    LanSyncPhase? phase,
    LanSyncDirection? direction,
    LanSyncEndpoint? local,
    LanSyncEndpoint? peer,
    LanSyncProgressDetail? detail,
  }) => LanSyncTransferProgress(
    phase: phase ?? this.phase,
    direction: direction ?? this.direction,
    local: local ?? this.local,
    peer: peer ?? this.peer,
    detail: detail ?? this.detail,
  );
}

double _ratio(int current, int total) {
  if (total <= 0) return 0;
  return (current / total).clamp(0, 1);
}

int _asInt(Object? value) => value is num ? value.round() : 0;
