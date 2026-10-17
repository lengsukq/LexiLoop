/// 局域网同步设置模型与发现报文模型的测试。
///
/// 覆盖三件容易写错的事：解析容错（设置表里可能是任何东西）、端口夹取、
/// 发现报文的往返与拒绝规则。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

void main() {
  group('parseLanSyncPort', () {
    test('缺失或非数字回落到默认端口', () {
      expect(parseLanSyncPort(null), lanSyncDefaultPort);
      expect(parseLanSyncPort('8080'), lanSyncDefaultPort);
      expect(parseLanSyncPort(<String, Object?>{}), lanSyncDefaultPort);
    });

    test('越界值被夹到可配置区间', () {
      expect(parseLanSyncPort(80), lanSyncMinPort);
      expect(parseLanSyncPort(70000), lanSyncMaxPort);
      expect(parseLanSyncPort(0), lanSyncMinPort);
      expect(parseLanSyncPort(-1), lanSyncMinPort);
    });

    test('区间内的值原样保留（浮点取整）', () {
      expect(parseLanSyncPort(8765), 8765);
      expect(parseLanSyncPort(9000.6), 9001);
    });
  });

  group('lanSyncSettingsFromRaw', () {
    test('非映射时给出兜底名与默认端口', () {
      final settings = lanSyncSettingsFromRaw(
        'not-a-map',
        fallbackDeviceName: '兜底',
      );
      expect(settings.deviceName, '兜底');
      expect(settings.port, lanSyncDefaultPort);
      expect(settings.lastSuccessAt, isNull);
      expect(settings.lastError, isNull);
      expect(settings.lastPeer, isNull);
    });

    test('缺少设备名时用兜底名填充', () {
      final settings = lanSyncSettingsFromRaw(<String, Object?>{
        'port': 9001,
      }, fallbackDeviceName: '兜底');
      expect(settings.deviceName, '兜底');
      expect(settings.port, 9001);
    });

    test('空白的设备名同样按缺失处理', () {
      final settings = lanSyncSettingsFromRaw(<String, Object?>{
        'deviceName': '   ',
      }, fallbackDeviceName: '兜底');
      expect(settings.deviceName, '兜底');
    });

    test('读取全部字段', () {
      final settings = lanSyncSettingsFromRaw(<String, Object?>{
        'deviceName': '书房 Mac',
        'port': 9123,
        'lastSuccessAt': 1792069100000,
        'lastError': 'LAN_SYNC_UNREACHABLE',
        'lastPeer': 'LexiLoop 手机（192.168.1.7）',
      }, fallbackDeviceName: '兜底');
      expect(settings.deviceName, '书房 Mac');
      expect(settings.port, 9123);
      expect(settings.lastSuccessAt, 1792069100000);
      expect(settings.lastError, 'LAN_SYNC_UNREACHABLE');
      expect(settings.lastPeer, 'LexiLoop 手机（192.168.1.7）');
    });

    test('非正的时间戳与空的错误码按缺失处理', () {
      final settings = lanSyncSettingsFromRaw(<String, Object?>{
        'lastSuccessAt': 0,
        'lastError': '  ',
        'lastPeer': '',
      }, fallbackDeviceName: '兜底');
      expect(settings.lastSuccessAt, isNull);
      expect(settings.lastError, isNull);
      expect(settings.lastPeer, isNull);
    });
  });

  group('LanSyncPullMode', () {
    test('默认是合并', () {
      expect(LanSyncSettings.defaults.pullMode, LanSyncPullMode.merge);
    });

    test('wire 往返一致', () {
      for (final mode in LanSyncPullMode.values) {
        expect(LanSyncPullMode.fromWire(mode.wire), mode);
      }
    });

    test('未知或缺失的取值回落到合并而不是覆盖', () {
      // 回落方向不能反：未知值来自更新版本，按合并处理不会删数据。
      expect(LanSyncPullMode.fromWire('SOMETHING_NEW'), LanSyncPullMode.merge);
      expect(LanSyncPullMode.fromWire(null), LanSyncPullMode.merge);
      expect(LanSyncPullMode.fromWire(''), LanSyncPullMode.merge);
    });

    test('落盘后能读回', () {
      const settings = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 8765,
        pullMode: LanSyncPullMode.replace,
      );
      final restored = lanSyncSettingsFromRaw(
        settings.toStorage(),
        fallbackDeviceName: '兜底',
      );
      expect(restored.pullMode, LanSyncPullMode.replace);
    });

    test('老版本存的映射里没有 pullMode 时按合并处理', () {
      final restored = lanSyncSettingsFromRaw(<String, Object?>{
        'deviceName': '旧配置',
        'port': 8765,
      }, fallbackDeviceName: '兜底');
      expect(restored.pullMode, LanSyncPullMode.merge);
    });

    test('copyWith 保留模式', () {
      const settings = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 8765,
        pullMode: LanSyncPullMode.replace,
      );
      expect(settings.copyWith(port: 9100).pullMode, LanSyncPullMode.replace);
      expect(
        settings.copyWith(pullMode: LanSyncPullMode.merge).pullMode,
        LanSyncPullMode.merge,
      );
    });
  });

  group('LanSyncSettings', () {
    test('toStorage → 解析 往返一致', () {
      const original = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 9123,
        lastSuccessAt: 42,
        lastError: 'LAN_SYNC_BUSY',
        lastPeer: '手机',
      );
      final restored = lanSyncSettingsFromRaw(
        original.toStorage(),
        fallbackDeviceName: '兜底',
      );
      expect(restored.deviceName, original.deviceName);
      expect(restored.port, original.port);
      expect(restored.lastSuccessAt, original.lastSuccessAt);
      expect(restored.lastError, original.lastError);
      expect(restored.lastPeer, original.lastPeer);
    });

    test('空设备名不落盘，读回时用兜底名', () {
      const settings = LanSyncSettings.defaults;
      expect(settings.toStorage().containsKey('deviceName'), isFalse);
      expect(
        lanSyncSettingsFromRaw(
          settings.toStorage(),
          fallbackDeviceName: 'LexiLoop 桌面',
        ).deviceName,
        'LexiLoop 桌面',
      );
    });

    test('effectiveDeviceName：填了用填的，空串用兜底', () {
      const named = LanSyncSettings(deviceName: '书房 Mac', port: 8765);
      const unnamed = LanSyncSettings.defaults;
      expect(named.effectiveDeviceName(fallback: '兜底'), '书房 Mac');
      expect(unnamed.effectiveDeviceName(fallback: '兜底'), '兜底');
    });

    test('copyWith 保留未提及的字段', () {
      const original = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 9123,
        lastSuccessAt: 42,
        lastError: 'LAN_SYNC_BUSY',
        lastPeer: '手机',
      );
      final updated = original.copyWith(port: 9000);
      expect(updated.deviceName, '书房 Mac');
      expect(updated.port, 9000);
      expect(updated.lastSuccessAt, 42);
      expect(updated.lastError, 'LAN_SYNC_BUSY');
      expect(updated.lastPeer, '手机');
    });

    test('clearError 能真正清掉上次失败原因', () {
      const original = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 9123,
        lastError: 'LAN_SYNC_BUSY',
        lastPeer: '手机',
      );
      final cleared = original.copyWith(lastSuccessAt: 99, clearError: true);
      expect(cleared.lastError, isNull);
      // 对端标签与错误原因无关，不该被顺手清掉。
      expect(cleared.lastPeer, '手机');
      expect(cleared.lastSuccessAt, 99);
    });

    test('clearPeer 能清掉对端标签', () {
      const original = LanSyncSettings(
        deviceName: '书房 Mac',
        port: 9123,
        lastPeer: '手机',
      );
      expect(original.copyWith(clearPeer: true).lastPeer, isNull);
    });

    test('defaults 用默认端口且设备名留给调用方兜底', () {
      expect(LanSyncSettings.defaults.port, lanSyncDefaultPort);
      expect(LanSyncSettings.defaults.deviceName, isEmpty);
    });
  });

  group('defaultLanSyncDeviceName', () {
    test('桌面与移动给出可区分的名字', () {
      final desktop = defaultLanSyncDeviceName(isDesktop: true);
      final mobile = defaultLanSyncDeviceName(isDesktop: false);
      expect(desktop, isNot(mobile));
      expect(desktop, startsWith(lexiloopDeviceNameDefault));
      expect(mobile, startsWith(lexiloopDeviceNameDefault));
    });
  });

  group('DiscoveredLanHost', () {
    const host = DiscoveredLanHost(
      instanceId: 'abc123',
      deviceName: 'LexiLoop 桌面',
      address: '192.168.1.7',
      port: 8765,
      protocolVersion: lanSyncProtocolVersion,
    );

    test('展示标签带地址，便于同名设备区分', () {
      expect(host.label, 'LexiLoop 桌面（192.168.1.7）');
    });

    test('没有设备名时只给地址', () {
      const anonymous = DiscoveredLanHost(
        instanceId: 'x',
        deviceName: '',
        address: '192.168.1.7',
        port: 8765,
        protocolVersion: lanSyncProtocolVersion,
      );
      expect(anonymous.label, '192.168.1.7');
    });

    test('baseUri 是可直接请求的 http 根地址', () {
      expect(host.baseUri.toString(), 'http://192.168.1.7:8765/');
    });

    test('toWire → parse 往返一致', () {
      final restored = parseDiscoveredLanHost(
        host.toWire(),
        address: host.address,
      );
      expect(restored, isNotNull);
      expect(restored!.instanceId, host.instanceId);
      expect(restored.deviceName, host.deviceName);
      expect(restored.address, host.address);
      expect(restored.port, host.port);
      expect(restored.protocolVersion, host.protocolVersion);
    });

    test('协议版本一致时 isCompatible 为真', () {
      expect(host.isCompatible, isTrue);
      const older = DiscoveredLanHost(
        instanceId: 'x',
        deviceName: '旧版',
        address: '192.168.1.9',
        port: 8765,
        protocolVersion: 0,
      );
      expect(older.isCompatible, isFalse);
    });
  });

  group('parseDiscoveredLanHost 的拒绝规则', () {
    Map<String, Object?> validWire() => <String, Object?>{
      'service': lanSyncServiceName,
      'version': lanSyncProtocolVersion,
      'kind': lanSyncDiscoveryReplyKind,
      'instanceId': 'abc',
      'device': '手机',
      'port': 8765,
    };

    DiscoveredLanHost? parse(Object? wire, {String address = '192.168.1.7'}) =>
        parseDiscoveredLanHost(wire, address: address);

    test('合法报文被接受', () {
      expect(parse(validWire()), isNotNull);
    });

    test('非映射被拒绝', () {
      expect(parse('nope'), isNull);
      expect(parse(null), isNull);
      expect(parse(<Object?>[]), isNull);
    });

    test('服务标识不符被拒绝', () {
      expect(
        parse(<String, Object?>{...validWire(), 'service': 'other'}),
        isNull,
      );
    });

    test('kind 是查询而不是应答时被拒绝', () {
      expect(parse(<String, Object?>{...validWire(), 'kind': 'query'}), isNull);
    });

    test('版本缺失或非正数被拒绝', () {
      expect(parse(<String, Object?>{...validWire(), 'version': 0}), isNull);
      expect(parse(<String, Object?>{...validWire(), 'version': 'v1'}), isNull);
    });

    test('端口越界或缺失被拒绝', () {
      expect(parse(<String, Object?>{...validWire(), 'port': 80}), isNull);
      expect(parse(<String, Object?>{...validWire(), 'port': 70000}), isNull);
      expect(parse(<String, Object?>{...validWire(), 'port': null}), isNull);
    });

    test('不合法或 IPv6 的地址被拒绝', () {
      expect(parse(validWire(), address: ''), isNull);
      expect(parse(validWire(), address: '192.168.1'), isNull);
      expect(parse(validWire(), address: '192.168.1.256'), isNull);
      expect(parse(validWire(), address: '::1'), isNull);
      // 前导零在部分解析器里是八进制，必须拒绝。
      expect(parse(validWire(), address: '192.168.001.7'), isNull);
    });

    test('版本不一致仍然解析出来（由调用方决定报什么错）', () {
      final parsed = parse(<String, Object?>{...validWire(), 'version': 99});
      expect(parsed, isNotNull);
      expect(parsed!.isCompatible, isFalse);
    });

    test('设备名缺失时解析为空串而不是失败', () {
      final parsed = parse(<String, Object?>{...validWire(), 'device': null});
      expect(parsed, isNotNull);
      expect(parsed!.deviceName, isEmpty);
    });
  });

  group('lanSyncDiscoveryQueryWire', () {
    test('是查询报文，且不是应答（不会被自己解析成设备）', () {
      final query = lanSyncDiscoveryQueryWire();
      expect(query['service'], lanSyncServiceName);
      expect(query['kind'], lanSyncDiscoveryQueryKind);
      expect(parseDiscoveredLanHost(query, address: '192.168.1.7'), isNull);
    });

    test('每次返回新的映射实例', () {
      expect(
        identical(lanSyncDiscoveryQueryWire(), lanSyncDiscoveryQueryWire()),
        isFalse,
      );
    });
  });
}
