/// 导出侧剥离 WebDAV 凭据的测试。
///
/// **为什么必须有这个测试**：这是一条只在「用户同时启用了远程备份」时才
/// 生效的路径，平时看不出来；一旦回归，服务器密码就会随备份上传到那台
/// 服务器本身，或被分享给任何拿到备份的人。断言必须直接读导出字节，
/// 而不是读内存里的设置对象。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  /// 写一份完整的 WebDAV 配置（含密码）。
  Future<void> writeWebdav({
    required String password,
    int autoIntervalMinutes = 0,
  }) => settings.update(<String, Object?>{
    webdavSettingsKey: webdavSettingsToStorage(
      WebdavSettings(
        credential: WebdavCredential(
          baseUrl: 'https://dav.example.com/dav',
          directory: '/LexiLoop/',
          username: 'leo',
          password: password,
        ),
        state: WebdavBackupState(
          autoIntervalMinutes: autoIntervalMinutes,
          lastSuccessAt: 1792069132000,
          lastCheckpoint: '1792069100000:1417',
        ),
      ),
    ),
  }, now: 1);

  /// 导出并按 `settings` 行取出 `webdavBackup` 的值。
  Future<Object?> exportedWebdavValue() async {
    final result = await BackupExporter(db).exportToJson();
    final decoded =
        jsonDecode(utf8.decode(result.bytes)) as Map<String, Object?>;
    final rows = (decoded['settings']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final row in rows) {
      if (row['key'] != webdavSettingsKey) continue;
      return jsonDecode(row['value_json']! as String);
    }
    return null;
  }

  test('导出的 webdavBackup 不含密码，其余字段保留', () async {
    await writeWebdav(password: '服务器密码', autoIntervalMinutes: 1440);

    final exported = await exportedWebdavValue();

    expect(exported, isA<Map<String, Object?>>());
    final map = exported! as Map<String, Object?>;
    expect(map.containsKey('password'), isFalse);
    expect(map['username'], 'leo');
    expect(map['baseUrl'], 'https://dav.example.com/dav');
    expect(map['directory'], '/LexiLoop/');
    expect(map['autoIntervalMinutes'], 1440);
    expect(map['lastSuccessAt'], 1792069132000);
    expect(map['lastCheckpoint'], '1792069100000:1417');
  });

  test('导出字节里不出现密码明文', () async {
    await writeWebdav(password: 'TOP-SECRET-PASSWORD');

    final result = await BackupExporter(db).exportToJson();

    expect(utf8.decode(result.bytes), isNot(contains('TOP-SECRET-PASSWORD')));
  });

  test('本地库里的密码不受导出影响', () async {
    await writeWebdav(password: 'app-pass');

    await BackupExporter(db).exportToJson();

    final reloaded = await SettingsService(SettingsDao(db)).load();
    final parsed = webdavSettingsFromRaw(reloaded.raw[webdavSettingsKey]);
    expect(parsed.credential!.password, 'app-pass');
  });

  test('没有 WebDAV 配置时其他设置键原样导出', () async {
    await settings.update(const <String, Object?>{
      'llmConfig': <String, Object?>{'apiKey': 'sk-keep-me'},
    }, now: 1);

    final result = await BackupExporter(db).exportToJson();

    expect(utf8.decode(result.bytes), contains('sk-keep-me'));
    expect(await exportedWebdavValue(), isNull);
  });
}
