/// 共享会话编排的测试。
///
/// 用真实的内存数据库与 `SettingsService`（服务端启动器换成替身）：
/// 「设备名与端口从设置里现读」这件事正是本类要负责的一半，
/// 把它也替掉就只剩下一堆没有内容的转发断言。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_lan_sync_client.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late LanSyncStateStore states;
  late FakeLanSyncHostStarter starter;
  late LanSyncShareService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    states = LanSyncStateStore(settings, clock: () => 1000);
    starter = FakeLanSyncHostStarter();
    service = LanSyncShareService(
      BackupExporter(db),
      starter.call,
      states,
      codeGenerator: () => '135790',
      instanceIdGenerator: () => 'instance-1',
    );
  });

  tearDown(() async {
    await service.stop();
    await db.close();
  });

  Future<LanSyncShareSession> start() =>
      service.start(onServed: () {}, onLockedOut: () {});

  group('start', () {
    test('配对码与设备名、端口来自设置', () async {
      await states.setPort(9100);
      await states.setDeviceName('书房 Mac');

      final session = await start();

      final options = starter.calls.single;
      expect(options.pairingCode, '135790');
      expect(options.instanceId, 'instance-1');
      expect(options.deviceName, '书房 Mac');
      expect(options.port, 9100);
      expect(session.baseUri, Uri.parse('http://192.168.1.7:8765/'));
      expect(session.servedCount, isZero);
      expect(session.isSharing, isTrue);
    });

    test('设备名没填过时用平台兜底名', () async {
      await start();
      expect(starter.calls.single.deviceName, isNotEmpty);
      expect(
        starter.calls.single.deviceName,
        startsWith(lexiloopDeviceNameDefault),
      );
    });

    test('重复调用不会起第二个服务端', () async {
      final first = await start();
      final second = await start();
      expect(starter.calls, hasLength(1));
      expect(identical(first, second), isTrue);
    });

    test('启动失败时原样抛出，且不留下会话', () async {
      starter.failure = const ValidationError(
        AppErrorCode.lanSyncHostStartFailed,
      );
      await expectLater(
        start(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncHostStartFailed,
          ),
        ),
      );
      expect(service.isSharing, isFalse);
      expect(service.session, isNull);
    });

    test('被错码踢下线之后再开启会先收干净上一个服务端', () async {
      final session = await start();
      final host = starter.host..lockOut();
      expect(session.isSharing, isTrue, reason: '快照是旧的，服务端仍在收尾');

      final restarted = await start();

      expect(host.stopCalls, 1);
      expect(starter.calls, hasLength(2));
      expect(restarted.lockedOut, isFalse);
    });
  });

  group('服务次数', () {
    test('服务端报数后快照与通知都会更新', () async {
      var notifications = 0;
      final session = await service.start(
        onServed: () => notifications += 1,
        onLockedOut: () {},
      );
      expect(session.servedCount, isZero);

      starter.host.serveOnce();

      expect(notifications, 1);
      expect(service.session!.servedCount, 1);
      // `start` 返回的是当时的快照，不回填；界面读的是 `service.session`。
      expect(session.servedCount, isZero);
    });
  });

  group('stop', () {
    test('停掉服务端并清空会话', () async {
      await start();
      await service.stop();
      expect(starter.host.stopCalls, 1);
      expect(service.session, isNull);
      expect(service.isSharing, isFalse);
    });

    test('可重复调用', () async {
      await start();
      await service.stop();
      await service.stop();
      expect(starter.host.stopCalls, 1);
    });

    test('没开共享时调用也不炸', () async {
      await service.stop();
      expect(starter.host.stopCalls, isZero);
    });
  });

  group('配对码错到上限', () {
    test('标记为已停止并通知界面', () async {
      var lockouts = 0;
      await service.start(onServed: () {}, onLockedOut: () => lockouts += 1);

      starter.host.lockOut();

      expect(lockouts, 1);
      final session = service.session;
      expect(session, isNotNull);
      expect(session!.lockedOut, isTrue);
      expect(session.isSharing, isFalse);
      // 配对码还在，界面才能说清「刚才那个码已经作废了」。
      expect(session.pairingCode, '135790');
    });
  });

  group('导出', () {
    test('备份源交出可解析的 JSON 与总行数', () async {
      await start();
      final backup = await starter.calls.single.backupSource();

      // 开启共享会自动落盘本机持久化 deviceId / datasetEpoch（settings 表 1 行）。
      expect(backup.totalRows, 1);
      expect(backup.fileName, startsWith(backupFilePrefixForTest));
      final decoded = jsonDecode(utf8.decode(backup.bytes));
      expect(decoded, isA<Map<String, Object?>>());
      expect((decoded as Map<String, Object?>)['format'], backupFormat);
      expect(decoded['words'], isEmpty);
    });
  });
}

/// 备份文件名前缀（避免在测试里 import 命名模块的一堆无关常量）。
const String backupFilePrefixForTest = 'lexiloop-backup-';
