/// 局域网同步在 Web 上的占位实现。
///
/// 由 `lan_sync_discovery.dart` 条件导入选中。浏览器里没有 UDP 套接字，
/// 也没有能用来推算子网广播的网卡列表，因此这里没有降级实现——
/// 搜索一律失败，文案指向「改用桌面端或移动端」。
///
/// 工厂本身**不抛**：界面会在 Web 上禁用整个分组，而把失败推迟到
/// [LanSyncDiscovery.discover] 让调用方的错误处理只有一条路径。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';

/// 创建一个永远失败的发现器。
LanSyncDiscovery createLanSyncDiscovery({int discoveryPort = 0}) =>
    const _WebLanSyncDiscovery();

/// Web 上的空实现。
class _WebLanSyncDiscovery implements LanSyncDiscovery {
  const new();

  @override
  Future<LanSyncDiscoveryResult> discover({required Duration timeout}) async {
    throw const ValidationError(AppErrorCode.lanSyncUnsupported);
  }
}
