/// 数据管理分组的 widget 测试。
///
/// 只测「导出这一步不能一按就发生」：真正的文件与分享面板是平台通道，
/// 交给 [FakeBackupExportService] 挡住；这里要钉住的是确认门与文案。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_management_section.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/services/backup/backup_export_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 假导出服务的依赖。
///
/// 打包成一个对象而不是裸传数据库：`BackupExportService` 的构造参数是私有
/// 字段形参，直接转发会触发 `use_super_parameters`。
class ExportDeps {
  const new(this.db);

  final AppDatabase db;
}

/// 不碰文件系统与分享面板的导出服务。
class FakeBackupExportService extends BackupExportService {
  new(ExportDeps deps) : super(BackupExporter(deps.db));

  /// 实际跑过几次 `exportAndShare`。
  int calls = 0;

  /// 下一次要抛出的错误。
  AppError? error;

  @override
  Future<SharedBackupExport> exportAndShare() async {
    calls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return SharedBackupExport(
      result: BackupExportResult(
        bytes: Uint8List.fromList(utf8.encode('{}')),
        rowCounts: const <String, int>{'words': 3, 'review_logs': 12},
      ),
      byteSize: 1024,
      filename: 'lexiloop-backup-20261014-222752.json',
    );
  }
}

void main() {
  late AppDatabase db;
  late FakeBackupExportService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = FakeBackupExportService(ExportDeps(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          backupExportServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: DataManagementSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('导出按钮存在且不直接执行', (tester) async {
    await pumpSection(tester);

    expect(find.byKey(const Key('exportBackup')), findsOneWidget);
    expect(find.text('导出 JSON 备份'), findsOneWidget);

    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exportBackupConfirmField')), findsOneWidget);
    expect(service.calls, 0, reason: '没敲关键字之前不许导出');
  });

  testWidgets('没敲对关键字时确认按钮保持禁用', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();

    VoidCallback? confirm() => tester
        .widget<FilledButton>(
          find.byKey(const Key('exportBackupConfirmButton')),
        )
        .onPressed;

    expect(confirm(), isNull);
    await tester.enterText(
      find.byKey(const Key('exportBackupConfirmField')),
      'export',
    );
    await tester.pumpAndSettle();
    expect(confirm(), isNull, reason: '大小写不匹配');

    await tester.enterText(
      find.byKey(const Key('exportBackupConfirmField')),
      'EXPORT',
    );
    await tester.pumpAndSettle();
    expect(confirm(), isNotNull);
  });

  testWidgets('确认后导出一次并汇报行数与字节数', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exportBackupConfirmField')),
      'EXPORT',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('exportBackupConfirmButton')));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.textContaining('已导出 15 行'), findsOneWidget);
    expect(find.textContaining('1.0 KB'), findsOneWidget);
  });

  testWidgets('取消后不导出', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exportBackupConfirmField')),
      'EXPORT',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
  });

  testWidgets('导出失败时把 AppError 文案弹给用户', (tester) async {
    service.error = const ValidationError(AppErrorCode.backupTooLarge);
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('exportBackupConfirmField')),
      'EXPORT',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportBackupConfirmButton')));
    await tester.pumpAndSettle();

    expect(find.text('备份文件过大。'), findsOneWidget);
  });

  testWidgets('清空全部数据的 DELETE 确认仍然生效', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('clearAllData')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('clearAllDataConfirmField')), findsOneWidget);
  });

  testWidgets('导入备份必须先敲 IMPORT——它是三个动作里唯一全量覆盖的', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.text('导入旧版 JSON 备份'));
    await tester.pumpAndSettle();

    // 对话框必须先出现，而不是直接开始导入。
    expect(find.byKey(const Key('importBackupConfirmField')), findsOneWidget);
    // 没敲关键字之前确认按钮必须禁用。
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('importBackupConfirmButton')),
          )
          .onPressed,
      isNull,
    );
    // 文案要点明这是「整体替换」而不是合并。**限定在对话框内**：同一页上
    // 还有别的分组（例如局域网同步）也会说「整体替换」，全局查找会撞车。
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('整体替换'),
      ),
      findsOneWidget,
    );
  });

  test('字节数格式化', () {
    expect(formatBackupBytes(512), '512 B');
    expect(formatBackupBytes(1024), '1.0 KB');
    expect(formatBackupBytes(27 * 1024 * 1024), '27.0 MB');
  });
}
