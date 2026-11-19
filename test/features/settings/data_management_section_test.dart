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

  testWidgets('点击导出按钮直接执行一次并汇报行数与字节数', (tester) async {
    await pumpSection(tester);

    expect(find.byKey(const Key('exportBackup')), findsOneWidget);
    expect(find.text('导出 JSON 备份'), findsOneWidget);

    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.textContaining('已导出 15 行'), findsOneWidget);
    expect(find.textContaining('1.0 KB'), findsOneWidget);
  });

  testWidgets('导出失败时把 AppError 文案弹给用户', (tester) async {
    service.error = const ValidationError(AppErrorCode.backupTooLarge);
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('exportBackup')));
    await tester.pumpAndSettle();

    expect(find.text('备份文件过大。'), findsOneWidget);
  });

  testWidgets('清空全部数据弹出底部危险确认抽屉', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.byKey(const Key('clearAllData')));
    await tester.pumpAndSettle();

    expect(find.text('清空全部数据？'), findsOneWidget);
    expect(
      find.byKey(const Key('clearAllDataConfirmButton')),
      findsOneWidget,
    );
  });

  testWidgets('导入备份弹出底部确认抽屉并说明是整体替换', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.text('导入旧版 JSON 备份'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('importBackupConfirmButton')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
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
