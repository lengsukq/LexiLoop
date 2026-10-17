/// 共享服务端的抽象端口。
///
/// **为什么要有这层接口**：与 `RemoteBackupClient`、`HttpFetcher`、
/// `SpeechEngine` 同一套约定——把「协议与平台」挡在业务逻辑之外。
/// 共享会话的编排（配对码、错码限流、服务次数、启停）只依赖这 3 个成员，
/// 测试里一个内存实现就能覆盖全部分支，不必真的监听一个端口。
///
/// 实现见 `lan_sync_host.dart` 的条件导出：原生端是 `dart:io` 的
/// `HttpServer`，Web 端直接抛「不支持」。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';

/// 一个正在运行的共享服务端。
abstract interface class LanSyncHost {
  /// 对端该连的根地址（`http://<本机 LAN IP>:<port>/`）。
  ///
  /// **只用于界面展示**：它取自本机第一张非环回网卡的地址，拼不出来的极端
  /// 情况下会回落到 `127.0.0.1`。真正的连接地址由对端从发现报文的来源地址
  /// 得到，不依赖这个值。
  Uri get baseUri;

  /// 已经成功服务过多少次拉取。
  ///
  /// 界面上显示它是有意义的：主机是纯被动的一方，用户唯一的「对方真的连上了」
  /// 反馈就是这个计数在涨。
  int get servedCount;

  /// 停止服务并释放端口；可重复调用。
  Future<void> stop();
}

/// 启动共享服务端所需的全部参数。
class LanSyncHostOptions {
  /// 以各字段构造。
  const new({
    required this.deviceName,
    required this.port,
    required this.pairingCode,
    required this.instanceId,
    required this.backupSource,
    required this.onCodeLockout,
    required this.onServed,
    this.discoveryPort = lanSyncDiscoveryPort,
  });

  /// 本机展示名（发现应答与握手响应都会带上）。
  final String deviceName;

  /// 监听的 TCP 端口。
  final int port;

  /// 本次会话的配对码。
  final String pairingCode;

  /// 本次共享会话的随机标识（用于让本机自己的发现请求过滤掉自己的应答）。
  final String instanceId;

  /// 应答发现查询的 UDP 端口。
  ///
  /// 对用户不可配置（见 `docs/LAN_SYNC.md` §3），留成参数只是为了让测试
  /// 能在同一条流水线上起多个实例而不互相抢端口。
  final int discoveryPort;

  /// 按需产出备份。
  final LanSyncBackupSource backupSource;

  /// 成功服务完一次拉取时回调，参数是累计次数。
  ///
  /// **主机是纯被动的一方**，用户唯一的「对方真的连上了」的反馈就是这个计数
  /// 在涨；回调而不是让界面轮询，是为了不引入一个只为刷新文案而存在的定时器。
  final void Function(int servedCount) onServed;

  /// 配对码连续错误到达上限时回调。
  ///
  /// **由调用方决定怎么停**：服务端自己只负责「数错了多少次」这件协议层的事，
  /// 「停掉共享并把状态写回设置」属于编排层。反过来把停共享写在服务端里，
  /// 服务端就得认识会话状态对象。
  final void Function() onCodeLockout;
}

/// 启动一个共享服务端。
///
/// 平台差异的唯一入口：Web 实现直接抛「浏览器里不支持」。
typedef LanSyncHostStarter = Future<LanSyncHost> Function(
  LanSyncHostOptions options,
);
