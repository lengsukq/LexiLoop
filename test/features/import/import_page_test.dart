/// 导入页的 widget 测试。
///
/// 文件选择是平台通道，测试里用 [CsvImportService] 的子类替换 `preview`，
/// 这样「解析 + 落库」之外的全部界面逻辑都还能真实跑一遍。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/import_page.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/services/csv_import_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 假服务的依赖。
///
/// 打包成一个对象而不是两个位置参数：`CsvImportService` 的构造参数是
/// 私有字段形参，无法用 `super.db` 转发，直接转发会触发
/// `use_super_parameters`。
class _FakeDeps {
  const new(this.db, this.settings);

  final AppDatabase db;
  final SettingsService settings;
}

/// 替换掉文件选择与提交的导入服务。
class _FakeImportService extends CsvImportService {
  new(
    _FakeDeps deps, {
    this.previewResult,
    this.previewError,
    this.commitResult,
  }) : super(deps.db, deps.settings);

  final ImportPreview? previewResult;
  final AppError? previewError;
  final ImportCommitResult? commitResult;

  /// 最近一次提交使用的模式，用于断言界面把选择传了下去。
  ImportMode? lastMode;
  bool? lastResetLearningProgress;

  @override
  Future<ImportPreview> preview({
    required String sourceLanguage,
    required String targetLanguage,
    required int now,
  }) async {
    final error = previewError;
    if (error != null) throw error;
    return previewResult!;
  }

  @override
  Future<ImportCommitResult> commit({
    required int batchId,
    required ImportMode mode,
    required bool resetLearningProgress,
    required int now,
  }) async {
    lastMode = mode;
    lastResetLearningProgress = resetLearningProgress;
    return commitResult!;
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

  ImportPreview buildPreview(String csv) {
    final parsed = parseEasyDictCsv(
      csv,
      sourceLanguage: 'en',
      targetLanguage: 'zh',
    );
    return ImportPreview(
      batchId: 7,
      filename: 'easydict.csv',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      createdAt: 1,
      expiresAt: 2,
      rows: parsed.rows,
      skippedCount: parsed.skippedCount,
    );
  }

  _FakeDeps deps() => _FakeDeps(db, settings);

  Future<void> pumpPage(WidgetTester tester, CsvImportService service) async {
    // 导入页是一整列卡片：把画布调高，避免「控件在屏幕外点不到」
    // 把测试失败误报成界面缺陷。
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          csvImportServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(theme: LexiTheme.light, home: const ImportPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('初始状态显示语言选择与选文件入口', (tester) async {
    await pumpPage(tester, _FakeImportService(deps()));

    expect(find.text('源语言'), findsOneWidget);
    expect(find.text('目标语言'), findsOneWidget);
    expect(find.byKey(const Key('importSourceLanguage')), findsOneWidget);
    expect(find.byKey(const Key('importTargetLanguage')), findsOneWidget);
    expect(find.byKey(const Key('importPickFile')), findsOneWidget);
    // 还没选文件时没有预览，也没有提交按钮。
    expect(find.byKey(const Key('importSubmit')), findsNothing);
    expect(find.text('还没有导入记录。'), findsOneWidget);
  });

  testWidgets('解析失败时显示中文错误消息', (tester) async {
    await pumpPage(
      tester,
      _FakeImportService(
        deps(),
        previewError: const ValidationError(AppErrorCode.csvMissingHeaders),
      ),
    );

    await tester.tap(find.byKey(const Key('importPickFile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('importErrorBanner')), findsOneWidget);
    expect(find.text('缺少必要列。'), findsOneWidget);
  });

  testWidgets('用户取消选择时不显示错误', (tester) async {
    await pumpPage(
      tester,
      _FakeImportService(
        deps(),
        previewError: const ValidationError(AppErrorCode.csvRequired),
      ),
    );

    await tester.tap(find.byKey(const Key('importPickFile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('importErrorBanner')), findsNothing);
  });

  testWidgets('预览渲染词条与状态，提交后显示结果摘要', (tester) async {
    final service = _FakeImportService(
      deps(),
      previewResult: buildPreview('单词,释义\napple,苹果\napple,苹果\n,空\n'),
      commitResult: const ImportCommitResult(
        batchId: 7,
        created: 1,
        existing: 0,
        duplicate: 1,
        invalid: 1,
        failed: 0,
        queuedInitializations: 1,
      ),
    );
    await pumpPage(tester, service);

    await tester.tap(find.byKey(const Key('importPickFile')));
    await tester.pumpAndSettle();

    // 两行都是 apple：一行新增、一行文件内重复。
    expect(find.text('apple'), findsNWidgets(2));
    expect(find.text('easydict.csv（3 行）'), findsOneWidget);
    expect(find.byKey(const Key('importSubmit')), findsOneWidget);

    await tester.tap(find.byKey(const Key('importSubmit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('importResultCard')), findsOneWidget);
    expect(find.textContaining('新增 1'), findsOneWidget);
    expect(service.lastMode, ImportMode.skipExisting);
  });

  testWidgets('切换导入模式后提交使用新模式', (tester) async {
    final service = _FakeImportService(
      deps(),
      previewResult: buildPreview('单词,释义\napple,苹果\n'),
      commitResult: const ImportCommitResult(
        batchId: 7,
        created: 1,
        existing: 0,
        duplicate: 0,
        invalid: 0,
        failed: 0,
        queuedInitializations: 1,
      ),
    );
    await pumpPage(tester, service);

    await tester.tap(find.byKey(const Key('importPickFile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增并补全缺失字段（FILL_MISSING）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('importSubmit')));
    await tester.pumpAndSettle();

    expect(service.lastMode, ImportMode.fillMissing);
  });

  group('重置学习进度', () {
    ImportCommitResult commitResult() => const ImportCommitResult(
      batchId: 7,
      created: 1,
      existing: 0,
      duplicate: 0,
      invalid: 0,
      failed: 0,
      queuedInitializations: 1,
    );

    testWidgets('默认不勾选，提交时也不重置', (tester) async {
      final service = _FakeImportService(
        deps(),
        previewResult: buildPreview('单词,释义\napple,苹果\n'),
        commitResult: commitResult(),
      );
      await pumpPage(tester, service);
      await tester.tap(find.byKey(const Key('importPickFile')));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(
        find.byKey(const Key('resetLearningProgress')),
      );
      expect(checkbox.value, isFalse);

      await tester.tap(find.byKey(const Key('importSubmit')));
      await tester.pumpAndSettle();

      expect(service.lastResetLearningProgress, isFalse);
    });

    testWidgets('勾选后必须二次确认才提交', (tester) async {
      final service = _FakeImportService(
        deps(),
        previewResult: buildPreview('单词,释义\napple,苹果\n'),
        commitResult: commitResult(),
      );
      await pumpPage(tester, service);
      await tester.tap(find.byKey(const Key('importPickFile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetLearningProgress')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('importSubmit')));
      await tester.pumpAndSettle();

      // 取消 = 什么都不发生。
      expect(find.byKey(const Key('resetProgressConfirm')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.lastResetLearningProgress, isNull);

      // 确认 = 把开关传下去。
      await tester.tap(find.byKey(const Key('importSubmit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetProgressConfirm')));
      await tester.pumpAndSettle();
      expect(service.lastResetLearningProgress, isTrue);
    });

    testWidgets('说明文案点明删除什么与不删什么', (tester) async {
      await pumpPage(
        tester,
        _FakeImportService(
          deps(),
          previewResult: buildPreview('单词,释义\napple,苹果\n'),
          commitResult: commitResult(),
        ),
      );
      await tester.tap(find.byKey(const Key('importPickFile')));
      await tester.pumpAndSettle();

      expect(find.text('重置已有词条的学习进度'), findsOneWidget);
      expect(find.textContaining('复习卡、复习日志、错词状态'), findsOneWidget);
      expect(find.textContaining('词典内容不删除'), findsOneWidget);
    });
  });
}
