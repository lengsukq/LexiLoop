/// 「搜索同网段共享设备」的 `dart:io` 实现：UDP 广播 + 收集单播应答。
///
/// **为什么要往多个地址各发一遍**：只发 `255.255.255.255` 时，报文走的是
/// 路由表的默认路由——而装了 VPN（Tailscale、Clash、公司隧道）的机器上，
/// 默认路由往往指向隧道接口，广播就再也出不了局域网。因此除有限广播之外，
/// 还对每张本机网卡按 /24 推出的子网广播地址各发一次：`192.168.1.255`
/// 这样的地址命中直连路由，会从对应的网卡出去。
///
/// **/24 是一个刻意的假设**：`dart:io` 的 `NetworkInterface` 只给地址、
/// 不给子网掩码，家里与办公室的局域网绝大多数就是 /24。假设不成立时
/// 还有 `255.255.255.255` 兜底。
///
/// 由 `lan_sync_discovery.dart` 条件导出。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 创建一个 UDP 发现器。
///
/// [discoveryPort] 对用户不可配置（见 `docs/LAN_SYNC.md` §3）；
/// 留成参数只是为了让测试用一条独立端口跑，不与被测主机抢同一个套接字。
LanSyncDiscovery createLanSyncDiscovery({
  int discoveryPort = lanSyncDiscoveryPort,
}) => _UdpLanSyncDiscovery(discoveryPort);

/// 有限广播地址。
const String _limitedBroadcast = '255.255.255.255';

/// IPv4 地址被 `.` 分成的段数。
const int _ipv4PartCount = 4;

/// /24 子网广播地址的最后一段。
const String _subnetBroadcastOctet = '255';

/// 基于 UDP 广播的发现器。
class _UdpLanSyncDiscovery implements LanSyncDiscovery {
  /// 以要发送到的发现端口构造。
  const new(this.discoveryPort);

  /// 目标 UDP 端口。
  final int discoveryPort;

  @override
  Future<LanSyncDiscoveryResult> discover({required Duration timeout}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final collector = _ReplyCollector();
    // `send` 到某张网卡的广播地址可能失败，而失败是异步报进事件流的
    // （与主机端同一个原因）。丢一条不影响其余网卡上的搜索。
    final subscription = socket.listen(
      (event) => collector.accept(socket, event),
      onError: (Object error) {
        // 某张网卡发不出去而已，其他网卡的应答照收。
      },
    );
    try {
      await _broadcast(socket);
      await Future<void>.delayed(timeout);
    } finally {
      // 先取消订阅再关套接字：关套接字会结束流，但显式取消能让
      // 「收报文 → 读套接字」之间不再有一次竞态。
      await subscription.cancel();
      socket.close();
    }
    return collector.result();
  }

  /// 向所有可能的广播地址各发一份查询。
  Future<void> _broadcast(RawDatagramSocket socket) async {
    final payload = utf8.encode(jsonEncode(lanSyncDiscoveryQueryWire()));
    final targets = await _broadcastTargets();
    for (final target in targets) {
      socket.send(payload, target, discoveryPort);
    }
  }
}

/// 收集应答报文并归成一次搜索结果。
class _ReplyCollector {
  final List<DiscoveredLanHost> _hosts = <DiscoveredLanHost>[];
  final Set<String> _incompatibleKeys = <String>{};

  /// 处理一次套接字事件并收下报文。
  ///
  /// 套接字随事件一起传进来：`receive` 只能从监听回调里调用，
  /// 而监听回调由 [_UdpLanSyncDiscovery] 注册。
  void accept(RawDatagramSocket socket, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null) return;
    final host = _decode(datagram);
    if (host == null) return;
    if (!host.isCompatible) {
      _incompatibleKeys.add(lanSyncHostKey(host));
      return;
    }
    _hosts.add(host);
  }

  /// 归成结果（去重、排序、截断都在 [lanSyncDiscoveryResult] 里）。
  LanSyncDiscoveryResult result() => lanSyncDiscoveryResult(
    hosts: _hosts,
    incompatibleHostCount: _incompatibleKeys.length,
  );

  /// 解析一条报文；不是本协议的有效应答时返回 `null`。
  DiscoveredLanHost? _decode(Datagram datagram) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram.data));
    } on FormatException {
      return null;
    }
    return parseDiscoveredLanHost(decoded, address: datagram.address.address);
  }
}

/// 本机可能发得出去的广播地址。
Future<List<InternetAddress>> _broadcastTargets() async {
  final targets = <String>{_limitedBroadcast};
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final subnet = _subnetBroadcast(address.address);
        if (subnet != null) targets.add(subnet);
      }
    }
  } on SocketException {
    // 枚举网卡失败时只剩有限广播；它在单默认路由的常见网络里够用。
  }
  return <InternetAddress>[
    for (final target in targets) ?InternetAddress.tryParse(target),
  ];
}

/// 按 /24 推出 `a.b.c.255`；不是 IPv4 字面量时返回 `null`。
String? _subnetBroadcast(String address) {
  final parts = address.split('.');
  if (parts.length != _ipv4PartCount) return null;
  return '${parts[0]}.${parts[1]}.${parts[2]}.$_subnetBroadcastOctet';
}
