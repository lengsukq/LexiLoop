/// Next.js 云端同步客户端抽象端口与取消信号。
library;

import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';

/// 跨层取消信号（避免服务层直接依赖 `dio` 的 `CancelToken`）。
class CloudSyncCancelSignal {
  /// 创建未取消的信号。
  new();

  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  /// 是否已请求取消。
  bool get isCancelled => _cancelled;

  /// 触发取消并通知全部已注册监听器。
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// 注册取消回调；若已取消则立即回调。
  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// 移除取消回调。
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

/// Next.js 云端同步 HTTP 客户端端口。
abstract interface class CloudSyncClient {
  /// 握手并校验密码与协议版本。
  Future<CloudSyncHandshakeReply> handshake(
    CloudSyncHandshakeRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  });

  /// 拉取一页增量或覆盖快照。
  Future<CloudSyncPullPage> pullPage(
    CloudSyncPullRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  });

  /// 推送一批增量数据。
  Future<CloudSyncPushReply> pushBatch(
    CloudSyncPushRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  });
}

/// 按服务器凭据构造 [CloudSyncClient] 的工厂函数。
typedef CloudSyncClientFactory = CloudSyncClient Function(
  CloudSyncCredential credential,
);
