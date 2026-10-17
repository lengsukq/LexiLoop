/// 局域网设备发现的测试。
///
/// 分两层：
/// - [lanSyncDiscoveryResult] 是纯函数，去重 / 排序 / 截断逐条断言；
/// - 真实 UDP 那一条只钉住「广播出去、单播回来、能解析成设备」这条链路。
///
/// 真实 UDP 用一条测试专用端口，避免打到真实应用监听的 8766。
/// 回应方绑 `anyIPv4`，因此既能收到 `255.255.255.255` 也能收到
/// 子网广播（如 `192.168.x.255`）——正是被测实现会发的两类地址。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

import '../../support/free_udp_port.dart';

void main() {
  group('lanSyncDiscoveryResult', () {
    DiscoveredLanHost host(
      String name, {
      String instanceId = '',
      String address = '192.168.1.7',
      int port = 8765,
      int version = lanSyncProtocolVersion,
    }) => DiscoveredLanHost(
      instanceId: instanceId,
      deviceName: name,
      address: address,
      port: port,
      protocolVersion: version,
    );

    test('按展示标签排序', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          host('书房 Mac', address: '192.168.1.9'),
          host('LexiLoop 手机'),
        ],
        incompatibleHostCount: 0,
      );
      expect(result.hosts.map((entry) => entry.deviceName), <String>[
        'LexiLoop 手机',
        '书房 Mac',
      ]);
    });

    test('同一会话标识只保留一台', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          host('书房 Mac', instanceId: 'same'),
          host('书房 Mac', instanceId: 'same', address: '192.168.1.9'),
        ],
        incompatibleHostCount: 0,
      );
      expect(result.hosts, hasLength(1));
      expect(result.hosts.single.address, '192.168.1.7');
    });

    test('会话标识缺失时按地址与端口去重，先到的那台留下', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          host('甲'),
          host('乙'),
          host('丙', address: '192.168.1.8'),
        ],
        incompatibleHostCount: 0,
      );
      expect(result.hosts, hasLength(2));
      expect(
        result.hosts
            .firstWhere((entry) => entry.address == '192.168.1.7')
            .deviceName,
        '甲',
      );
    });

    test('超过上限时截断，且保留排在最前的那几台', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          for (var index = 0; index < lanSyncMaxListedHosts + 5; index++)
            host(
              '设备 ${index.toString().padLeft(2, '0')}',
              address: '192.168.1.${index + 10}',
            ),
        ],
        incompatibleHostCount: 0,
      );
      expect(result.hosts, hasLength(lanSyncMaxListedHosts));
      expect(result.hosts.first.deviceName, '设备 00');
      expect(result.hosts.last.deviceName, '设备 09');
    });

    test('不兼容设备数原样带出', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[],
        incompatibleHostCount: 3,
      );
      expect(result.hosts, isEmpty);
      expect(result.incompatibleHostCount, 3);
    });

    test('空输入给出空结果', () {
      final result = lanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[],
        incompatibleHostCount: 0,
      );
      expect(result.hosts, isEmpty);
      expect(result.incompatibleHostCount, isZero);
    });
  });

  group('真实 UDP 发现', () {
    late _Responder responder;
    late int port;
    late LanSyncDiscovery discovery;

    setUp(() async {
      port = await freeUdpPort();
      responder = _Responder(port);
      await responder.start();
      discovery = createLanSyncDiscovery(discoveryPort: port);
    });

    tearDown(() => responder.stop());

    test('广播一次就能发现同网段的设备', () async {
      responder.replyWith(
        _reply(instanceId: 'peer-1', deviceName: 'LexiLoop 手机'),
      );
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );
      expect(result.hosts, hasLength(1));
      expect(result.hosts.single.deviceName, 'LexiLoop 手机');
      expect(result.hosts.single.port, 8765);
      // 地址来自数据报的来源地址，对方自报的地址不作数。
      expect(result.hosts.single.address, isNot('10.0.0.1'));
      expect(result.incompatibleHostCount, isZero);
    });

    test('同一会话回两次也只算一台', () async {
      responder
        ..replyWith(_reply(instanceId: 'peer-1', deviceName: 'LexiLoop 手机'))
        ..replyWith(_reply(instanceId: 'peer-1', deviceName: 'LexiLoop 手机'));
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );
      expect(result.hosts, hasLength(1));
    });

    test('版本不一致的应答计入不兼容数，不进可用列表', () async {
      responder.replyWith(
        _reply(
          instanceId: 'peer-old',
          deviceName: '旧版设备',
          version: lanSyncProtocolVersion + 1,
        ),
      );
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );
      expect(result.hosts, isEmpty);
      expect(result.incompatibleHostCount, 1);
    });

    test('没有回应时返回空结果而不是抛错', () async {
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.hosts, isEmpty);
      expect(result.incompatibleHostCount, isZero);
    });

    test('非本协议的报文被忽略', () async {
      responder.replyWith(<String, Object?>{'hello': 'world'});
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.hosts, isEmpty);
    });

    test('不是合法 JSON 的报文被忽略', () async {
      responder.replyRaw(utf8.encode('{ this is not json'));
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.hosts, isEmpty);
    });

    test('把查询报文当成应答回复也认不出来（kind 不符）', () async {
      responder.replyWith(lanSyncDiscoveryQueryWire());
      final result = await discovery.discover(
        timeout: const Duration(milliseconds: 200),
      );
      expect(result.hosts, isEmpty);
    });
  });
}

/// 一条合法的发现应答。
Map<String, Object?> _reply({
  required String instanceId,
  required String deviceName,
  int port = 8765,
  int version = lanSyncProtocolVersion,
}) => <String, Object?>{
  'service': lanSyncServiceName,
  'version': version,
  'kind': lanSyncDiscoveryReplyKind,
  'instanceId': instanceId,
  'device': deviceName,
  'port': port,
  // 这一栏是被测实现**不会**采信的：地址应当来自数据报来源。
  'address': '10.0.0.1',
};

/// 一个只在测试期间存在的发现应答器。
class _Responder {
  /// 以要监听的端口构造。
  new(this.port);

  /// 监听的 UDP 端口。
  final int port;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final List<List<int>> _payloads = <List<int>>[];

  /// 绑定端口并开始应答。
  Future<void> start() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    _socket = socket;
    _subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        // 同机回环投递时内核可能把来源地址留成 `0.0.0.0`，此时回给它发不出去；
        // 这是测试夹具的处境，真实对端看到的永远是本机的实际网卡地址。
        final target = datagram.address.address == '0.0.0.0'
            ? InternetAddress.loopbackIPv4
            : datagram.address;
        for (final payload in _payloads) {
          socket.send(payload, target, datagram.port);
        }
      },
      onError: (Object error) {
        // 同上：回给一张不可路由的地址时失败是异步报进来的。
      },
    );
  }

  /// 追加一条要回给提问者的报文。
  void replyWith(Map<String, Object?> payload) =>
      replyRaw(utf8.encode(jsonEncode(payload)));

  /// 追加一条原始字节报文。
  void replyRaw(List<int> payload) => _payloads.add(payload);

  /// 关闭。
  Future<void> stop() async {
    await _subscription?.cancel();
    _socket?.close();
  }
}
