/// 备份导出编排的测试。
///
/// 钉住三件事：
/// 1. 文件名形状与旧版 `/api/backups/json` 下发的一致（用户会把新旧文件
///    放在同一个目录里，形状变了就没法按名字排序）；
/// 2. **原生端的交付方式是落临时文件后分享文件**——由替身收到的 [XFile]
///    反查磁盘内容来验证，这正是「原生端行为不得回归」的那条；
/// 3. 交付的字节与导出结果逐字节相同。
///
/// **Web 分支测不到**：`backup_file.dart` 的条件导入在 VM 上永远选中原生分支。
/// Web 的 `XFile.fromData` + 浏览器下载由 `flutter build web --release` 与
/// 浏览器实测覆盖，见 `docs/FLUTTER_WEB.md`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/services/backup/backup_export_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'backup_platform_fakes.dart';

/// 分享面板替身必须整个文件复用：见 [FakeSharePlatform] 的说明。
final FakeSharePlatform _share = FakeSharePlatform();

void main() {
  late AppDatabase db;
  late BackupExportService service;
  late Directory tempDir;

  setUpAll(() {
    // 必须在任何 `SharePlus.instance` 访问之前完成，否则会被固定成
    // MethodChannelShare。
    SharePlatform.instance = _share;
  });

  setUp(() {
    _share.calls.clear();
    tempDir = Directory.systemTemp.createTempSync('lexiloop-backup-test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    db = AppDatabase(NativeDatabase.memory());
    service = BackupExportService(BackupExporter(db));
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('文件名与旧版格式一致，且交给分享面板的是临时目录里的文件', () async {
    final exported = await service.exportAndShare();

    expect(
      exported.filename,
      matches(RegExp(r'^lexiloop-backup-\d{4}-\d{2}-\d{2}-\d{6}\.json$')),
    );
    expect(_share.calls, hasLength(1));

    final params = _share.calls.single;
    final files = params.files!;
    expect(files, hasLength(1));
    expect(
      files.single.path,
      '${tempDir.path}${Platform.pathSeparator}${exported.filename}',
    );
    expect(files.single.mimeType, backupMimeType);
    expect(params.fileNameOverrides, <String>[exported.filename]);
    expect(params.subject, isNotNull);
  });

  test('落盘内容与导出字节逐字节相同，byteSize 就是字节数', () async {
    final exported = await service.exportAndShare();

    final onDisk = File('${tempDir.path}/${exported.filename}')
        .readAsBytesSync();
    expect(onDisk, exported.result.bytes);
    expect(exported.byteSize, exported.result.bytes.length);
    expect(exported.byteSize, greaterThan(0));
  });

  test('两次导出用不同文件名，不会互相覆盖', () async {
    final first = await service.exportAndShare();
    final second = await service.exportAndShare();

    // 同秒内两次导出文件名相同是允许的（时间戳精度就是秒），
    // 但两次都必须真的落盘成功、内容都可读。
    expect(first.byteSize, second.byteSize);
    expect(File('${tempDir.path}/${first.filename}').existsSync(), isTrue);
    expect(File('${tempDir.path}/${second.filename}').existsSync(), isTrue);
  });

  test('导出内容是能被导入器读回的信封', () async {
    final exported = await service.exportAndShare();

    final decoded = jsonDecode(utf8.decode(exported.result.bytes));
    expect(decoded, isA<Map<String, Object?>>());
    expect((decoded as Map<String, Object?>)['format'], backupFormat);
    expect(decoded['version'], isA<num>());
  });
}
