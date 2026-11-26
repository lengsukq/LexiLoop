/// 词库页「导入备份」必须与设置页用同一道确认门。
///
/// 收敛前这里零确认：选完文件就整份替换 12 张表。而同样的动作在
/// 设置 › 数据管理里要求打字输入 `IMPORT`。入口越显眼（它就在
/// 「手动添加」旁边），门槛反而越低——正好反了。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/import_backup_confirm.dart';
import 'package:lexiloop/features/words/widgets/import_backup_button.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/backup_service.dart';

import '../../support/app_harness.dart';

/// 记录调用次数的假备份服务。
class _RecordingBackupService implements BackupService {
  int calls = 0;

  @override
  Future<BackupImportResult?> pickAndImport() async {
    calls += 1;
    return null;
  }
}

void main() {
  late _RecordingBackupService service;

  setUp(() => service = _RecordingBackupService());

  Future<void> pumpButton(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      wrapWithScope(
        const Scaffold(body: Center(child: ImportBackupButton())),
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          backupServiceProvider.overrideWithValue(service),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('点「导入备份」先弹打字确认，取消则一次都不导入', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('导入备份'));
    await tester.pumpAndSettle();

    expect(find.text('导入 JSON 备份？'), findsOneWidget);
    expect(service.calls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.calls, 0);
  });

  testWidgets('在底部确认抽屉点「导入并覆盖」后才真的调用导入', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('导入备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(importBackupConfirmButtonKey));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
  });
}
