/// Next.js 云端同步的进度与结果模型（纯 Dart）。
library;

import 'package:lexiloop/domain/models/cloud_sync_settings.dart';

/// 云端同步执行阶段。
enum CloudSyncPhase {
  /// 正在与服务端握手并鉴权。
  connecting,

  /// 正在分页拉取服务端数据。
  pulling,

  /// 正在分批压缩推送本机变更。
  pushing,

  /// 正在本机单事务合入与重算 FSRS。
  merging,

  /// 同步已完成。
  completed,

  /// 同步失败。
  failed,

  /// 用户已取消。
  cancelled,
}

/// 同步过程中的实时进度快照。
class CloudSyncProgress {
  /// 以阶段、已完成步数、总步数、已传输字节与提示文案构造。
  const new({
    required this.phase,
    this.completedSteps = 0,
    this.totalSteps = 0,
    this.transferredBytes = 0,
    this.message = '',
  });

  /// 当前阶段。
  final CloudSyncPhase phase;

  /// 当前阶段已完成的页/批次数。
  final int completedSteps;

  /// 当前阶段预计总页/批次数（未知时为 0）。
  final int totalSteps;

  /// 累计网络传输字节数。
  final int transferredBytes;

  /// 面向界面的简短阶段提示。
  final String message;

  /// 是否仍在活跃进行中。
  bool get isActive =>
      phase == CloudSyncPhase.connecting ||
      phase == CloudSyncPhase.pulling ||
      phase == CloudSyncPhase.pushing ||
      phase == CloudSyncPhase.merging;

  /// 0–1 进度比例；步数未知时返回 `null`（展示不确定进度条）。
  double? get fraction =>
      totalSteps > 0 ? (completedSteps / totalSteps).clamp(0, 1) : null;
}

/// 单侧（本机或云端）一次合并的统计摘要。
class CloudSyncSideCounts {
  /// 以各统计字段构造。
  const new({
    this.addedWords = 0,
    this.updatedWords = 0,
    this.addedLogs = 0,
    this.rebuiltWords = 0,
    this.wordCount = 0,
  });

  /// 零统计哨兵。
  static const CloudSyncSideCounts zero = CloudSyncSideCounts();

  /// 新增词条数。
  final int addedWords;

  /// 元数据更新词条数。
  final int updatedWords;

  /// 新增作答日志数。
  final int addedLogs;

  /// 重放 FSRS 的词条数。
  final int rebuiltWords;

  /// 完成后该侧词条总数。
  final int wordCount;

  /// 累加另一批推送结果（用于多批推送汇总）。
  CloudSyncSideCounts accumulate(CloudSyncSideCounts other) =>
      CloudSyncSideCounts(
        addedWords: addedWords + other.addedWords,
        updatedWords: updatedWords + other.updatedWords,
        addedLogs: addedLogs + other.addedLogs,
        rebuiltWords: rebuiltWords + other.rebuiltWords,
        wordCount: other.wordCount > 0 ? other.wordCount : wordCount,
      );
}

/// 一次云端同步完成后的汇总结果。
class CloudSyncResult {
  /// 以同步模式、本机与云端摘要、传输字节及是否增量构造。
  const new({
    required this.mode,
    required this.local,
    this.peer = CloudSyncSideCounts.zero,
    this.transferredBytes = 0,
    this.isIncremental = false,
  });

  /// 本次执行的同步模式。
  final CloudSyncMode mode;

  /// 本机侧合并或替换摘要。
  final CloudSyncSideCounts local;

  /// 云端侧合并摘要（单向拉取或覆盖时为零）。
  final CloudSyncSideCounts peer;

  /// 本次网络实际传输总字节数。
  final int transferredBytes;

  /// 本次拉取是否命中增量水位线。
  final bool isIncremental;
}
