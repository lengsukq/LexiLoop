/// 备份导入编排的测试。
///
/// 钉住的性质只有一条，但它是这次 Web 化的核心：
/// **导入读的是字节，不是本地路径**。Android 的 `content://` 与浏览器里
/// file_picker 给出的 blob/data URI 都没有本地路径，旧实现
/// `File(files.first.path!)` 在这两端必然失败——而它恰好是「Web 上导入备份」
/// 唯一的入口。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/services/backup_service.dart';

import 'backup_platform_fakes.dart';

void main() {
  late AppDatabase db;
  late BackupService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = BackupService(BackupImporter(db));
  });

  tearDown(() async {
    await db.close();
  });

  /// 用导出器造一份真实备份，避免手写 JSON 与格式漂移。
  Future<Uint8List> buildBackupBytes() async {
    final exported = await BackupExporter(db).exportToJson();
    return exported.bytes;
  }

  test('没有本地路径的云文件也能导入', () async {
    final picked = CloudPlatformFile(
      name: 'lexiloop-backup.json',
      bytes: await buildBackupBytes(),
    );
    // 前提断言：这份输入确实没有本地路径。少了它，用例会退化成
    // 「读路径也能过」，钉不住这次修复。
    expect(picked.path, isNull);

    FilePickerPlatform.instance = FakeFilePickerPlatform(<PlatformFile>[
      picked,
    ]);
    final result = await service.pickAndImport();

    expect(result, isNotNull);
    // 12 张表都被走到：证明整份字节真的送进了导入器，而不是只读了开头。
    expect(result!.rowCounts.keys, BackupImporter.tableOrder);
  });

  test('用户取消时返回 null', () async {
    FilePickerPlatform.instance = FakeFilePickerPlatform(
      const <PlatformFile>[],
    );

    expect(await service.pickAndImport(), isNull);
  });

  test('选择器按 json 扩展名过滤', () async {
    final picker = FakeFilePickerPlatform(const <PlatformFile>[]);
    FilePickerPlatform.instance = picker;

    await service.pickAndImport();

    expect(picker.lastAllowedExtensions, <String>['json']);
    expect(picker.lastDialogTitle, isNotNull);
  });

  test('非 UTF-8 字节归一为备份格式错误而不是裸 FormatException', () async {
    // 0xFF 在 UTF-8 里永远非法。
    final broken = CloudPlatformFile(
      name: 'broken.json',
      bytes: Uint8List.fromList(<int>[0xFF, 0xFE, 0xFD]),
    );
    FilePickerPlatform.instance = FakeFilePickerPlatform(<PlatformFile>[
      broken,
    ]);

    await expectLater(
      service.pickAndImport(),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.backupInvalidFormat,
        ),
      ),
    );
  });

  test('合法 UTF-8 但内容不是备份时抛备份格式错误', () async {
    final notABackup = CloudPlatformFile(
      name: 'notes.json',
      bytes: Uint8List.fromList(utf8.encode('{"hello":"world"}')),
    );
    FilePickerPlatform.instance = FakeFilePickerPlatform(<PlatformFile>[
      notABackup,
    ]);

    await expectLater(
      service.pickAndImport(),
      throwsA(
        isA<AppError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.backupInvalidFormat,
        ),
      ),
    );
  });
}
