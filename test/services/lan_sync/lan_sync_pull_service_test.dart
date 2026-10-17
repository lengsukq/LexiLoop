/// 局域网拉取服务的测试。
///
/// 用真实的内存数据库跑完整导入：本类要负责的一半是「把字节交给
/// `BackupImporter` 并处理它前后的两件事」，替掉导入器就只剩转发断言。
/// 客户端与发现器换成替身，于是错码、版本不符、并发等分支不必伪造网络。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_lan_sync_client.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late LanSyncStateStore states;
  late FakeLanSyncClient client;
  late FakeLanSyncClientFactory factory;
  late FakeLanSyncDiscovery discovery;
  late BackupMergeService merger;
  late LanSyncPullService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    states = LanSyncStateStore(settings, clock: () => 5000);
    client = FakeLanSyncClient();
    factory = FakeLanSyncClientFactory(client);
    discovery = FakeLanSyncDiscovery();
    merger = BackupMergeService(
      BackupExporter(db),
      BackupImporter(db),
      settings,
      clock: () => 5000,
    );
    service = LanSyncPullService(
      factory.call,
      discovery,
      BackupImporter(db),
      merger,
      states,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 从被替换后的库里读出词条文本。
  Future<List<String>> terms() async {
    final rows = await db
        .customSelect('SELECT term FROM words ORDER BY term')
        .get();
    return rows.map((row) => row.read<String>('term')).toList();
  }

  group('discover', () {
    test('按固定的搜索超时调用发现器', () async {
      await service.discover();
      expect(discovery.calls, 1);
      expect(discovery.lastTimeout?.inMilliseconds, lanSyncDiscoveryTimeoutMs);
    });

    test('剔除本机自己的共享会话', () async {
      discovery.result = LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          fakeDiscoveredHost(instanceId: 'self', deviceName: '本机'),
          fakeDiscoveredHost(deviceName: '手机'),
        ],
        incompatibleHostCount: 2,
      );

      final result = await service.discover(excludeInstanceId: 'self');

      expect(result.hosts.map((host) => host.instanceId), <String>['peer-1']);
      // 不兼容计数与「谁在共享」无关，不该被剔除逻辑影响。
      expect(result.incompatibleHostCount, 2);
    });

    test('没传会话标识时原样返回', () async {
      discovery.result = LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[fakeDiscoveredHost(instanceId: 'self')],
        incompatibleHostCount: 0,
      );
      final result = await service.discover();
      expect(result.hosts, hasLength(1));
    });

    test('发现器抛错时原样上抛，不记失败状态', () async {
      discovery.failure = const ValidationError(
        AppErrorCode.lanSyncUnsupported,
      );
      await expectLater(service.discover(), throwsA(isA<AppError>()));
      expect((await states.load()).lastError, isNull);
    });
  });

  group('pull 成功路径', () {
    setUp(() async {
      // 本机先有一份数据与一套自己的设置。
      await _seed(db, <String>['beta']);
      await states.setDeviceName('书房 Mac');
      await states.setPort(9100);
      client.backupResult = _backupOf(<String>['alpha', 'gamma']);
    });

    test('合并模式下用对端的词条补齐本地，本机原有的保留', () async {
      final result = await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );
      expect(await terms(), <String>['alpha', 'beta', 'gamma']);
      expect(result.mode, LanSyncPullMode.merge);
      expect(result.addedWords, 2, reason: 'alpha 与 gamma 是新增的');
      expect(result.updatedWords, isZero);
      expect(result.addedLogs, isZero);
      expect(result.wordCount, 3);
    });

    test('覆盖模式下整份替换', () async {
      final result = await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.replace,
      );
      expect(await terms(), <String>['alpha', 'gamma']);
      expect(result.mode, LanSyncPullMode.replace);
      expect(result.addedWords, 2);
      expect(result.wordCount, 2);
    });

    test('先握手验码，再下载字节', () async {
      await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );
      expect(client.calls, <String>['handshake', 'download']);
    });

    test('把目标设备与配对码原样交给工厂', () async {
      final host = fakeDiscoveredHost(address: '10.1.2.3', port: 9001);
      await service.pull(
        host: host,
        pairingCode: '246810',
        mode: LanSyncPullMode.merge,
      );
      expect(factory.calls.single.host, same(host));
      expect(factory.calls.single.code, '246810');
    });

    test('回写本机的设备名与端口，不被对端覆盖', () async {
      await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );
      final restored = await states.load();
      expect(restored.deviceName, '书房 Mac');
      expect(restored.port, 9100);
    });

    test('记录成功时间与对端标签，并清掉上次的失败原因', () async {
      await states.recordFailure(AppErrorCode.lanSyncUnreachable.code);

      await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );

      final after = await states.load();
      expect(after.lastSuccessAt, 5000);
      expect(after.lastError, isNull);
      expect(after.lastPeer, 'LexiLoop 手机（192.168.1.7）');
    });

    test('对端没给设备名时用发现列表里的设备名兜底', () async {
      client.handshakeResult = const LanSyncHandshake(
        deviceName: '',
        protocolVersion: lanSyncProtocolVersion,
      );
      await service.pull(
        host: fakeDiscoveredHost(deviceName: '手机', address: '192.168.1.9'),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );
      expect((await states.load()).lastPeer, '手机（192.168.1.9）');
    });

    test('即使本地数据被整份替换，设置表里的其它键仍来自对端', () async {
      // 对端带来的设置里没有 lanSync；`restore` 只补这一个键。
      await service.pull(
        host: fakeDiscoveredHost(),
        pairingCode: '135790',
        mode: LanSyncPullMode.merge,
      );
      final raw = (await settings.load()).raw;
      expect(raw.containsKey(lanSyncSettingsKey), isTrue);
    });
  });

  group('pull 失败路径', () {
    setUp(() async {
      await _seed(db, <String>['beta']);
    });

    test('配对码错误：不导入、不改本地数据、记下错误码', () async {
      client.handshakeFailure = const ValidationError(
        AppErrorCode.lanSyncCodeInvalid,
      );

      await expectLater(
        service.pull(
          host: fakeDiscoveredHost(),
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

      expect(await terms(), <String>['beta']);
      expect(client.calls, <String>['handshake']);
      final after = await states.load();
      expect(after.lastError, AppErrorCode.lanSyncCodeInvalid.code);
      expect(after.lastSuccessAt, isNull);
    });

    test('下载失败：不导入、不改本地数据、记下错误码', () async {
      client.downloadFailure = const ExternalServiceError(
        AppErrorCode.lanSyncUnreachable,
      );

      await expectLater(
        service.pull(
          host: fakeDiscoveredHost(),
          pairingCode: '135790',
          mode: LanSyncPullMode.merge,
        ),
        throwsA(isA<AppError>()),
      );

      expect(await terms(), <String>['beta']);
      expect(
        (await states.load()).lastError,
        AppErrorCode.lanSyncUnreachable.code,
      );
    });

    test('下载到的不是合法备份：记「格式无效」且本地数据不变', () async {
      client.backupResult = LanSyncBackup(
        bytes: Uint8List.fromList(utf8.encode('not json at all')),
        fileName: 'broken.json',
        totalRows: 0,
      );

      await expectLater(
        service.pull(
          host: fakeDiscoveredHost(),
          pairingCode: '135790',
          mode: LanSyncPullMode.merge,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidJson,
          ),
        ),
      );

      expect(await terms(), <String>['beta']);
      expect(
        (await states.load()).lastError,
        AppErrorCode.backupInvalidJson.code,
      );
    });

    test('失败不会把本机的设备名与端口弄丢', () async {
      await states.setDeviceName('书房 Mac');
      await states.setPort(9100);
      client.downloadFailure = const ExternalServiceError(
        AppErrorCode.lanSyncUnreachable,
      );

      await expectLater(
        service.pull(
          host: fakeDiscoveredHost(),
          pairingCode: '135790',
          mode: LanSyncPullMode.merge,
        ),
        throwsA(isA<AppError>()),
      );

      final after = await states.load();
      expect(after.deviceName, '书房 Mac');
      expect(after.port, 9100);
    });
  });
}

/// 用一份最小合法备份把 [db] 播种成给定词条的库。
Future<void> _seed(AppDatabase db, List<String> words) async {
  final result = _backupOf(words);
  await BackupImporter(db).import(utf8.decode(result.bytes));
}

/// 造一份含给定词条的最小合法备份。
LanSyncBackup _backupOf(List<String> words) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final payload = jsonEncode(<String, Object?>{
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
  return LanSyncBackup(
    bytes: Uint8List.fromList(utf8.encode(payload)),
    fileName: 'lexiloop-backup-2026-10-16-101500.json',
    totalRows: words.length,
  );
}
