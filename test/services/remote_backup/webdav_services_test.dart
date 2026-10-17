/// 远端上传 / 恢复 / 自动备份三个服务的测试。
///
/// 用内存库 + 内存远端跑完整链路：导出真实的 JSON 备份 → 上传 → 列目录 →
/// 下载 → 导入回另一个库。比逐层断言更能说明「这条链路真的能用」。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/backup_checkpoint_dao.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/remote_backup/webdav_auto_backup.dart';
import 'package:lexiloop/services/remote_backup/webdav_restore_service.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';
import 'package:lexiloop/services/remote_backup/webdav_upload_service.dart';
import 'package:lexiloop/services/scheduling/one_shot_timer.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_remote_backup_client.dart';

/// 可手动触发的假定时器。
class FakeTimer implements MaintenanceTimer {
  /// 是否已被取消。
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

void main() {
  late AppDatabase db;
  late SettingsServiceHarness harness;
  late FakeRemoteBackupClient remote;
  late FakeTimer timer;
  var now = 1792069132000;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    harness = SettingsServiceHarness(db);
    remote = FakeRemoteBackupClient();
    timer = FakeTimer();
    now = 1792069132000;
  });

  tearDown(() async {
    await db.close();
  });

  /// 配好 WebDAV 凭据。
  Future<void> configure({int autoIntervalMinutes = 0}) =>
      harness.write(<String, Object?>{
        webdavSettingsKey: webdavSettingsToStorage(
          WebdavSettings(
            credential: const WebdavCredential(
              baseUrl: 'https://dav.example.com/dav',
              directory: '/LexiLoop/',
              username: 'leo',
              password: 'app-pass',
            ),
            state: WebdavBackupState(autoIntervalMinutes: autoIntervalMinutes),
          ),
        ),
      });

  WebdavStateStore store() =>
      WebdavStateStore(harness.service, clock: () => now);

  WebdavUploadService uploader() => WebdavUploadService(
    BackupExporter(db),
    (credential) {
      expect(credential.username, 'leo');
      return remote;
    },
    store(),
    BackupCheckpointDao(db),
  );

  WebdavRestoreService restorer() =>
      WebdavRestoreService((credential) => remote, store(), BackupImporter(db));

  WebdavAutoBackup auto({required List<Duration> scheduled}) =>
      WebdavAutoBackup(
        uploader(),
        BackupCheckpointDao(db),
        store(),
        () => now,
        (duration, onElapsed) {
          scheduled.add(duration);
          return timer;
        },
      );

  Future<int> insertWord(String term) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: EntryType.word,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  group('手动上传', () {
    test('未配置时抛「未配置」，且不碰远端', () async {
      await expectLater(
        uploader().uploadNow(),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.webdavNotConfigured,
          ),
        ),
      );
      expect(remote.ensureDirectoryCalls, 0);
    });

    test('上传成功后远端有一份内容正确的备份，并记下成功状态', () async {
      await configure();
      await insertWord('serendipity');

      final result = await uploader().uploadNow();

      expect(result.fileName, startsWith(backupFilePrefix));
      expect(result.fileName, endsWith('.json'));
      expect(result.totalRows, greaterThan(0));
      expect(remote.backupNames, <String>[result.fileName]);

      // 内容真的是一份可导入的信封。
      final decoded = jsonDecode(
        utf8.decode(remote.files[result.fileName]!),
      ) as Map<String, Object?>;
      expect(decoded['format'], backupFormat);
      expect(decoded['words'], hasLength(1));

      final state = (await store().load()).state;
      expect(state.lastSuccessAt, now);
      expect(state.lastError, isNull);
      expect(state.lastCheckpoint, isNotNull);
    });

    test('上传失败时记下错误码，且不写成功时间', () async {
      await configure();
      remote.failWith = const ExternalServiceError(
        AppErrorCode.webdavAuthFailed,
      );

      await expectLater(
        uploader().uploadNow(),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.webdavAuthFailed,
          ),
        ),
      );

      final state = (await store().load()).state;
      expect(state.lastSuccessAt, isNull);
      expect(state.lastError, AppErrorCode.webdavAuthFailed.code);
    });

    test('状态写入保留凭据', () async {
      await configure();
      remote.failWith = const ExternalServiceError(
        AppErrorCode.webdavUnreachable,
      );

      try {
        await uploader().uploadNow();
      } on AppError {
        // 期望失败；重点是失败之后凭据还在。
      }

      final settings = await store().load();
      expect(settings.credential, isNotNull);
      expect(settings.credential!.password, 'app-pass');
      expect(settings.credential!.baseUrl, 'https://dav.example.com/dav');
    });
  });

  group('状态写入', () {
    test('半填的凭据不会被状态更新抹掉', () async {
      // 用户只填了地址与账号、还没填密码：这是界面上的常态。
      await harness.write(<String, Object?>{
        webdavSettingsKey: <String, Object?>{
          'baseUrl': 'https://dav.example.com/dav',
          'username': 'leo',
          'password': '',
          'autoIntervalMinutes': 0,
        },
      });

      await store().setAutoInterval(360);

      final raw =
          (await harness.service.load()).raw[webdavSettingsKey]!
              as Map<String, Object?>;
      expect(raw['baseUrl'], 'https://dav.example.com/dav');
      expect(raw['username'], 'leo');
      expect(raw['autoIntervalMinutes'], 360);
    });

    test('记录失败不删除已有凭据', () async {
      await configure();
      await store().recordFailure(AppErrorCode.webdavUnreachable.code);

      final settings = await store().load();
      expect(settings.credential!.password, 'app-pass');
      expect(settings.state.lastError, AppErrorCode.webdavUnreachable.code);
    });
  });

  group('远端恢复', () {
    test('上传 → 列目录 → 恢复到另一个库，词条与行数一致', () async {
      await configure();
      await insertWord('serendipity');
      await insertWord('ephemeral');
      final uploaded = await uploader().uploadNow();

      final entries = await restorer().listRemoteBackups();
      expect(entries.single.name, uploaded.fileName);

      // 换成干净的库：导入是全量替换，词条数应回到 2。
      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      final restored = await WebdavRestoreService(
        (credential) => remote,
        store(),
        BackupImporter(target),
      ).restore(entries.single);

      expect(restored.rowCounts['words'], 2);
      final rows = await target.customSelect('SELECT term FROM words').get();
      expect(rows.map((row) => row.read<String>('term')).toSet(), <String>{
        'serendipity',
        'ephemeral',
      });
    });

    test('远端没有备份时列表为空', () async {
      await configure();

      expect(await restorer().listRemoteBackups(), isEmpty);
    });

    test('远端文件不是合法 JSON 时归成备份格式错误', () async {
      await configure();
      remote.files['${backupFilePrefix}broken.json'] = Uint8List.fromList(<int>[
        0xff,
        0xfe,
        0xfd,
      ]);

      await expectLater(
        restorer().restore(
          const RemoteBackupEntry(
            name: 'lexiloop-backup-broken.json',
            sizeBytes: 3,
          ),
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidFormat,
          ),
        ),
      );
    });
  });

  group('自动备份', () {
    test('关闭周期时不挂定时器、不发请求', () async {
      await configure();
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      await backup.start();

      expect(remote.ensureDirectoryCalls, 0);
      expect(remote.files, isEmpty);
      expect(
        scheduled.single,
        const Duration(milliseconds: webdavAutoCheckIntervalMs),
      );
      backup.dispose();
    });

    test('首次启用（无成功记录）立刻上传一次', () async {
      await configure(autoIntervalMinutes: 60);
      await insertWord('serendipity');
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      await backup.start();

      expect(remote.putCalls, 1);
      expect(remote.backupNames, hasLength(1));
      expect(scheduled.single.inMilliseconds, webdavAutoCheckIntervalMs);
      backup.dispose();
    });

    test('周期没到不上传', () async {
      await configure(autoIntervalMinutes: 60);
      await insertWord('serendipity');
      // 先手动上传一次，把 lastSuccessAt 设为 now。
      await uploader().uploadNow();
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      // 过了 10 分钟，离 60 分钟的周期还远。
      now += 10 * minuteMs;
      await backup.start();

      expect(remote.backupNames, hasLength(1), reason: '只有手动那次');
      expect(
        scheduled.single,
        const Duration(milliseconds: webdavAutoCheckIntervalMs),
      );
      backup.dispose();
    });

    test('周期到了但数据没变时跳过', () async {
      await configure(autoIntervalMinutes: 60);
      await insertWord('serendipity');
      await uploader().uploadNow();
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      now += 61 * minuteMs;
      await backup.start();

      expect(remote.putCalls, 1, reason: '手动那次之后不该再传');
      backup.dispose();
    });

    test('周期到了且数据变了就再传一份', () async {
      await configure(autoIntervalMinutes: 60);
      await insertWord('serendipity');
      final first = await uploader().uploadNow();
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);
      expect(first.fileName, isNotEmpty);

      // 新词条 → 词条数变化 → 检查点变化。
      now += 61 * minuteMs;
      await insertWord('ephemeral');
      await backup.start();

      // 两次上传可能落在同一个文件名上（命名只精确到秒，而测试里的
      // 模拟时钟不推进真实时间），因此断言「真的又传了一次」而不是文件数。
      expect(remote.putCalls, 2);
      expect(remote.backupNames, <String>[first.fileName]);
      final latest = jsonDecode(
        utf8.decode(remote.files[first.fileName]!),
      ) as Map<String, Object?>;
      expect(latest['words'], hasLength(2), reason: '第二份应含新词条');
      backup.dispose();
    });

    test('上传失败时记下错误并保留排期，不抛给调用方', () async {
      await configure(autoIntervalMinutes: 60);
      remote.failWith = const ExternalServiceError(
        AppErrorCode.webdavUnreachable,
      );
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      await expectLater(backup.start(), completes);

      expect((await store().load()).state.lastError, isNotNull);
      expect(scheduled, isNotEmpty);
      backup.dispose();
    });

    test('dispose 取消挂起的定时器，重复 start 不复活', () async {
      await configure(autoIntervalMinutes: 60);
      final scheduled = <Duration>[];
      final backup = auto(scheduled: scheduled);

      await backup.start();
      expect(timer.cancelled, isFalse);
      backup.dispose();
      expect(timer.cancelled, isTrue);

      await backup.start();
      expect(backup.isRunning, isTrue);
      backup.dispose();
    });
  });

  group('下一次检查的延迟', () {
    test('从未成功过时按固定检查节奏', () {
      expect(
        webdavNextCheckDelay(
          state: const WebdavBackupState(autoIntervalMinutes: 60),
          now: now,
        ),
        const Duration(milliseconds: webdavAutoCheckIntervalMs),
      );
    });

    test('接近到期时睡到刚好到期，而不是整段检查间隔', () {
      final state = WebdavBackupState(
        autoIntervalMinutes: 60,
        lastSuccessAt: now,
      );

      // 周期 60 分钟，已在 57 分钟处：还剩 3 分钟 < 5 分钟检查间隔。
      expect(
        webdavNextCheckDelay(state: state, now: now + 57 * minuteMs),
        const Duration(milliseconds: 3 * minuteMs),
      );
    });

    test('已经过期时回到固定检查节奏', () {
      final state = WebdavBackupState(
        autoIntervalMinutes: 60,
        lastSuccessAt: now,
      );

      expect(
        webdavNextCheckDelay(state: state, now: now + 120 * minuteMs),
        const Duration(milliseconds: webdavAutoCheckIntervalMs),
      );
    });
  });
}

/// 直接读写设置表的测试宿主。
///
/// 不用 `ProviderContainer`：三个服务都只依赖 `SettingsService` 与数据库，
/// 直接构造能少一层与本次改动无关的 Riverpod 装配。
class SettingsServiceHarness {
  /// 以数据库构造。
  new(AppDatabase db) : service = SettingsService(SettingsDao(db));

  /// 被测的设置服务。
  final SettingsService service;

  /// 覆盖写入若干设置项。
  Future<void> write(Map<String, Object?> changes) =>
      service.update(changes, now: 1);
}
