/// 导入历史区域的撤销确认测试。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/import_history_section.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/services/csv_import_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

class _RollbackTrackingService extends CsvImportService {
  new(super._db, super._settings, this.batch);

  final ImportBatchSummary batch;
  int rollbackCalls = 0;

  @override
  Future<List<ImportBatchSummary>> recentBatches() async =>
      <ImportBatchSummary>[batch];

  @override
  Future<void> rollback({required int batchId, required int now}) async {
    rollbackCalls++;
  }
}

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

  testWidgets('撤销确认显示批次信息和整批阻断，取消不调用撤销服务', (tester) async {
    final batch = ImportBatchSummary(
      id: 4,
      filename: 'words-2026.csv',
      status: ImportBatchStatus.committed,
      importMode: ImportMode.skipExisting,
      totalRows: 3,
      validRows: 3,
      invalidRows: 0,
      duplicateRows: 0,
      createdWords: 3,
      existingWords: 0,
      queuedInitializations: 3,
      createdAt: DateTime(2026, 3, 1, 10, 5).millisecondsSinceEpoch,
      resetLearningProgress: false,
    );
    final service = _RollbackTrackingService(db, settings, batch);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          csvImportServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: ImportHistorySection()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('撤销这次导入？'), findsOneWidget);
    expect(find.textContaining('来源文件：words-2026.csv'), findsOneWidget);
    expect(find.textContaining('创建时间：2026-03-01 10:05'), findsOneWidget);
    expect(find.textContaining('将删除本批次新增的 3 个词条及其内容。'), findsOneWidget);
    expect(find.textContaining('系统将拒绝整批撤销，不会部分删除。'), findsOneWidget);
    expect(service.rollbackCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('撤销这次导入？'), findsNothing);
    expect(service.rollbackCalls, 0);
    expect(await db.select(db.words).get(), isEmpty);
  });
}
