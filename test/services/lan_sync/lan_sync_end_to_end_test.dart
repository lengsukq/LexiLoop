/// 局域网同步的端到端测试（真 HTTP、真导出、真导入，只把「发现」换掉）。
///
/// **为什么还要这一层**：主机用例与客户端用例各自断言了「我发的请求长什么样」，
/// 但它们读的是同一份协议常量——一个两边都不一致的拼写错误会同时通过两层。
/// 这里让真实的服务端与真实的客户端对打，路径、请求头、响应头、状态码、字节
/// 与导入结果全部串起来验一遍。
///
/// 唯一被替换的是**发现**：真实的 UDP 广播打到局域网上没有意义，
/// 而且 CI 机器未必有非环回网卡。发现本身由
/// `test/data/lan_sync/lan_sync_discovery_test.dart` 覆盖。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_lan_sync_client.dart';
import '../../support/free_udp_port.dart';

void main() {
  late AppDatabase hostDb;
  late AppDatabase clientDb;
  late SettingsService hostSettings;
  late SettingsService clientSettings;
  late LanSyncHost host;
  late DiscoveredLanHost target;
  late int discoveryPort;
  const pairingCode = '864213';

  setUp(() async {
    hostDb = AppDatabase(NativeDatabase.memory());
    clientDb = AppDatabase(NativeDatabase.memory());
    hostSettings = SettingsService(SettingsDao(hostDb));
    clientSettings = SettingsService(SettingsDao(clientDb));

    // 主机的库里有 alpha 与 gamma。
    await BackupImporter(hostDb)
        .import(_backupJson(<String>['alpha', 'gamma']));
    await LanSyncStateStore(hostSettings).setDeviceName('主机的名字');

    // 客户端的库里只有 beta，并带一份自己的设备名与端口。
    await BackupImporter(clientDb).import(_backupJson(<String>['beta']));
    await LanSyncStateStore(clientSettings).setDeviceName('客户端的名字');
    await LanSyncStateStore(clientSettings).setPort(9100);

    discoveryPort = await freeUdpPort();
    host = await createLanSyncHost(
      LanSyncHostOptions(
        deviceName: '主机的名字',
        port: 0,
        pairingCode: pairingCode,
        instanceId: 'e2e-instance',
        discoveryPort: discoveryPort,
        backupSource: () async {
          final exported = await BackupExporter(hostDb).exportToJson();
          return LanSyncBackup(
            bytes: exported.bytes,
            fileName: backupFileName(DateTime.now()),
            totalRows: exported.totalRows,
          );
        },
        onServed: (count) {},
        onCodeLockout: () {},
      ),
    );
    target = DiscoveredLanHost(
      instanceId: 'e2e-instance',
      deviceName: '主机的名字',
      address: '127.0.0.1',
      port: host.baseUri.port,
      protocolVersion: lanSyncProtocolVersion,
    );
  });

  tearDown(() async {
    await host.stop();
    await hostDb.close();
    await clientDb.close();
  });

  /// 客户端的词条。
  Future<List<String>> clientTerms() async {
    final rows = await clientDb
        .customSelect('SELECT term FROM words ORDER BY term')
        .get();
    return rows.map((row) => row.read<String>('term')).toList();
  }

  LanSyncPullService pullService() => LanSyncPullService(
    LanSyncHttpClient.new,
    FakeLanSyncDiscovery(),
    BackupImporter(clientDb),
    BackupMergeService(
      BackupExporter(clientDb),
      BackupImporter(clientDb),
      clientSettings,
      clock: () => 777,
    ),
    LanSyncStateStore(clientSettings, clock: () => 777),
  );

  test('合并：主机的词条加进来，本机原有的留下', () async {
    final result = await pullService().pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.merge,
    );

    // 本机原有 beta，主机有 alpha 与 gamma：合并后三个都在。
    expect(await clientTerms(), <String>['alpha', 'beta', 'gamma']);
    expect(result.mode, LanSyncPullMode.merge);
    expect(result.addedWords, 2);
    expect(result.wordCount, 3);
    expect(host.servedCount, 1);
  });

  test('覆盖：整份替换，本机原有的 beta 被清掉', () async {
    final result = await pullService().pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.replace,
    );

    expect(await clientTerms(), <String>['alpha', 'gamma']);
    expect(result.mode, LanSyncPullMode.replace);
    expect(result.addedWords, 2);
    expect(result.wordCount, 2);
  });

  test('导入之后本机的设备名与端口没有被主机覆盖', () async {
    await pullService().pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.merge,
    );

    final settings = await LanSyncStateStore(clientSettings).load();
    expect(settings.deviceName, '客户端的名字');
    expect(settings.port, 9100);
  });

  test('成功后记下成功时间与对端标签', () async {
    await pullService().pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.merge,
    );

    final settings = await LanSyncStateStore(clientSettings).load();
    expect(settings.lastSuccessAt, 777);
    expect(settings.lastPeer, '主机的名字（127.0.0.1）');
  });

  test('配对码错误时不传任何字节，也不改本地数据', () async {
    await expectLater(
      pullService().pull(
        host: target,
        pairingCode: '000000',
        mode: LanSyncPullMode.merge,
      ),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.lanSyncCodeInvalid,
        ),
      ),
    );

    expect(await clientTerms(), <String>['beta']);
    expect(host.servedCount, isZero);
  });

  test('主机停掉共享之后拉取报「连不上对方」', () async {
    await host.stop();

    await expectLater(
      pullService().pull(
        host: target,
        pairingCode: pairingCode,
        mode: LanSyncPullMode.merge,
      ),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.lanSyncUnreachable,
        ),
      ),
    );
    expect(await clientTerms(), <String>['beta']);
  });

  test('连续两次合并仍然成功（连接没有被上一次弄脏，且幂等）', () async {
    final service = pullService();
    await service.pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.merge,
    );
    final second = await service.pull(
      host: target,
      pairingCode: pairingCode,
      mode: LanSyncPullMode.merge,
    );
    expect(await clientTerms(), <String>['alpha', 'beta', 'gamma']);
    expect(second.addedWords, isZero, reason: '第二次没有新词条');
    expect(host.servedCount, 2);
  });

  test('真实的 HTTP 客户端与服务端在同一个进程里也不互相卡住', () async {
    // 这条用例的价值在并发：dio 的连接池 + HttpServer 的单请求串行化
    // 若有一方没关响应，这里会超时而不是通过。
    final service = pullService();
    await Future.wait(<Future<void>>[
      service.pull(
        host: target,
        pairingCode: pairingCode,
        mode: LanSyncPullMode.merge,
      ),
    ]);
    expect(await clientTerms(), <String>['alpha', 'beta', 'gamma']);
  });

  test('真实的发现器能在同机上找到这个服务端', () async {
    // **只广播是打不回来的**：需要一张非环回网卡才能真正发出子网广播，
    // 而 CI 容器里常常只有 loopback。没有就跳过，不制造假失败。
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final hasLanInterface = interfaces.any(
      (interface) => interface.addresses.any((address) => !address.isLoopback),
    );
    if (!hasLanInterface) {
      markTestSkipped('本机没有非环回 IPv4 网卡，跳过真实的 UDP 发现');
      return;
    }

    final discovery = createLanSyncDiscovery(discoveryPort: discoveryPort);
    final result = await discovery.discover(
      timeout: const Duration(milliseconds: 400),
    );
    expect(
      result.hosts.map((entry) => entry.instanceId),
      contains('e2e-instance'),
    );
  });

  test('回环地址被识别为合法目标', () {
    // 端到端用的是 `127.0.0.1`，因此发现模型必须接受它。
    expect(target.baseUri.toString(), 'http://127.0.0.1:${host.baseUri.port}/');
    expect(target.isCompatible, isTrue);
  });
}

/// 造一份含给定词条的最小合法备份 JSON。
String _backupJson(List<String> words) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return jsonEncode(<String, Object?>{
    'format': backupFormat,
    'version': 3,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'words': <Map<String, Object?>>[
      for (final (index, term) in words.indexed)
        <String, Object?>{
          'id': index + 1,
          'term': term,
          'normalized_term': term.toLowerCase(),
          'source_language': 'en',
          'target_language': 'zh',
          'entry_type': 'WORD',
          'content_type': 'WORD',
          'initialization_status': 'READY',
          'mastery_level': 'NEW',
          'mastery_score': 0,
          'is_suspended': 0,
          'created_at': now,
          'updated_at': now,
        },
    ],
  });
}
