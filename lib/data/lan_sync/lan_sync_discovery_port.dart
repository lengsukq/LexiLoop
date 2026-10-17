/// 「搜索同网段共享设备」的抽象端口。
///
/// 与 `LanSyncHost` 同样是平台接缝：原生端用 UDP 广播，Web 端直接抛
/// 「浏览器里不支持」。测试注入一个内存实现即可覆盖发现之后的全部分支。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 一次搜索的结果。
///
/// **为什么要区分「没有设备」与「只有版本不兼容的设备」**：这两种情况给用户
/// 的下一步完全不同——前者要去检查网络和对方的开关，后者只需要把自己或对方
/// 升级到同一版本。只返回一个空列表会把后者也说成「没搜到」，
/// 用户就会去折腾一个本来没问题的网络。
class LanSyncDiscoveryResult {
  /// 以可用设备与不兼容设备数构造。
  const new({required this.hosts, required this.incompatibleHostCount});

  /// 协议版本一致的设备（按设备名排序，已去重并截断）。
  final List<DiscoveredLanHost> hosts;

  /// 收到了应答、但协议版本不一致的设备数量。
  final int incompatibleHostCount;

  /// 什么都没有搜到。
  static const LanSyncDiscoveryResult empty = LanSyncDiscoveryResult(
    hosts: <DiscoveredLanHost>[],
    incompatibleHostCount: 0,
  );
}

/// 把收到的原始应答归成一次搜索结果。
///
/// **写成纯函数**：去重、排序、截断这三件事都有各自的边界情况
/// （同一台设备回了两次、名字为空、应答多于上限），而在真套接字上构造
/// 这些场景既慢又不稳。抽出来之后可以逐条断言，实现里只负责收字节。
///
/// 去重键优先用对端的会话标识：同一台设备的一次共享会话只会有一个标识，
/// 而它可能因为重传或多次广播被收到好几遍。标识缺失时退到地址与端口。
LanSyncDiscoveryResult lanSyncDiscoveryResult({
  required Iterable<DiscoveredLanHost> hosts,
  required int incompatibleHostCount,
}) {
  final byKey = <String, DiscoveredLanHost>{};
  for (final host in hosts) {
    byKey.putIfAbsent(lanSyncHostKey(host), () => host);
  }
  final sorted = byKey.values.toList(growable: false)
    ..sort((a, b) => a.label.compareTo(b.label));
  return LanSyncDiscoveryResult(
    hosts: sorted.take(lanSyncMaxListedHosts).toList(growable: false),
    incompatibleHostCount: incompatibleHostCount,
  );
}

/// 一台设备在一次搜索里的去重键。
String lanSyncHostKey(DiscoveredLanHost host) =>
    host.instanceId.isEmpty ? '${host.address}:${host.port}' : host.instanceId;

/// 同网段设备的搜索入口。
abstract interface class LanSyncDiscovery {
  /// 广播一次并收集 [timeout] 内的应答。
  ///
  /// **不抛「没搜到」**：空结果是正常返回值，由调用方决定用哪种文案。
  /// 只有平台不支持（Web）才抛。
  Future<LanSyncDiscoveryResult> discover({required Duration timeout});
}
