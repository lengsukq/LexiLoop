/// 真实 HTTP 的 WebDAV 端到端验证（默认跳过）。
///
/// **为什么要有这一条**：其余 WebDAV 测试都在替换 `dio` 的传输层，因此
/// 「我们发的请求符合 WebDAV」是被断言的，但「真的和一台 WebDAV 服务器
/// 谈得下来」没有被验证过。这条用例把整条链路（建目录 → 上传 → 列目录 →
/// 下载 → 导入另一个库）跑在真实 HTTP 上。
///
/// 启动测试服务器（标准库实现，无第三方依赖）：
///
/// ```bash
/// python3 tool/webdav_test_server.py 8765 /tmp/lexiloop-dav-root &
/// LEXILOOP_WEBDAV_SMOKE_URL=http://127.0.0.1:8765 \
///   flutter test test/data/remote_backup/webdav_live_smoke_test.dart
/// ```
///
/// 也可以指向真实服务（坚果云 / 群晖 / Nextcloud）：
/// 额外设置 `LEXILOOP_WEBDAV_SMOKE_USER` / `LEXILOOP_WEBDAV_SMOKE_PASSWORD`，
/// 并确保目录里没有别人的重要文件——本用例只追加，不删除。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/data/remote_backup/webdav_client.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';

/// 测试服务器地址；未设置时整组用例跳过。
final String? smokeUrl = Platform.environment['LEXILOOP_WEBDAV_SMOKE_URL'];

/// 账号与密码（与测试服务器脚本的默认值一致）。
final String smokeUser =
    Platform.environment['LEXILOOP_WEBDAV_SMOKE_USER'] ?? 'leo';
final String smokePassword =
    Platform.environment['LEXILOOP_WEBDAV_SMOKE_PASSWORD'] ?? 'app-pass';

void main() {
  final target = smokeUrl;
  if (target == null || target.isEmpty) {
    test('真实 WebDAV 端到端（未设置 LEXILOOP_WEBDAV_SMOKE_URL，跳过）', () {
      // 空用例：让「跳过了什么」在输出里可见，而不是静默不跑。
    }, skip: '未设置 LEXILOOP_WEBDAV_SMOKE_URL');
    return;
  }

  WebdavCredential credential({
    String? password,
    String directory = 'LexiLoop',
  }) => WebdavCredential(
    baseUrl: target,
    directory: normalizeWebdavDirectory(directory),
    username: smokeUser,
    password: password ?? smokePassword,
  );

  test('建目录 → 上传 → 列目录 → 下载 → 导入，全程真实 HTTP', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final destination = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(destination.close);

    // 造两条最小可用的词条，让导出内容不是空壳。
    const now = 1792069132000;
    for (final term in <String>['serendipity', 'ephemeral']) {
      await source
          .into(source.words)
          .insert(
            WordsCompanion.insert(
              term: term,
              normalizedTerm: term,
              sourceLanguage: 'en',
              targetLanguage: 'zh-CN',
              entryType: EntryType.word,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    final client = WebdavClient(credential());
    await client.ensureDirectory();

    final exported = await BackupExporter(source).exportToJson();
    final fileName = backupFileName(DateTime.now());
    await client.putBackup(fileName: fileName, bytes: exported.bytes);

    final entries = await client.listBackups();
    final listed = entries.firstWhere(
      (entry) => entry.name == fileName,
      orElse: () => throw StateError(
        '刚上传的 $fileName 没出现在列表里：'
        '${entries.map((entry) => entry.name).toList()}',
      ),
    );
    expect(listed.sizeBytes, exported.bytes.length);

    final downloaded = await client.downloadBackup(listed);
    expect(downloaded, exported.bytes, reason: '下载字节应与上传逐字节相同');

    final restored = await BackupImporter(destination)
        .import(utf8.decode(downloaded));
    expect(restored.rowCounts['words'], 2);
    final rows = await destination
        .customSelect('SELECT term FROM words ORDER BY term')
        .get();
    expect(rows.map((row) => row.read<String>('term')).toList(), <String>[
      'ephemeral',
      'serendipity',
    ]);
  });

  test('子目录不存在时逐级创建', () async {
    final empty = AppDatabase(NativeDatabase.memory());
    addTearDown(empty.close);
    final client = WebdavClient(credential(directory: 'LexiLoop/nested/deep'));
    await client.ensureDirectory();

    final exported = await BackupExporter(empty).exportToJson();
    const fileName = 'lexiloop-backup-1970-01-01-000000.json';
    await client.putBackup(fileName: fileName, bytes: exported.bytes);

    final entries = await client.listBackups();
    expect(entries.map((entry) => entry.name), contains(fileName));
  });

  test('密码错误时归成鉴权失败，而不是网络不可用', () async {
    final client = WebdavClient(credential(password: 'wrong-password'));

    await expectLater(
      client.ensureDirectory(),
      throwsA(
        isA<ExternalServiceError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.webdavAuthFailed,
        ),
      ),
    );
  });

  test('下载不存在的那一份归成 notFound', () async {
    final client = WebdavClient(credential());

    await expectLater(
      client.downloadBackup(
        const RemoteBackupEntry(
          name: 'lexiloop-backup-1970-01-01-000000.json',
          sizeBytes: 0,
        ),
      ),
      throwsA(
        isA<NotFoundError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.webdavNotFound,
        ),
      ),
    );
  });
}
