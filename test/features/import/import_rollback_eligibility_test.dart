/// `ImportBatchSummary.canRollback` 与 `CsvImportService.rollback` 的判定必须一致。
///
/// 旧版实现只判了 `committed && existingWords == 0`，而服务层还要求
/// `importMode == SKIP_EXISTING` 且未重置学习进度。结果是按钮亮着、一按就报
/// 「该批次无法无损撤销」。本文件把两种 (status, importMode, existingWords,
/// resetLearningProgress) 组合逐一跑过服务层，用真结果反查模型的判定，
/// 任何一边改了条件而另一边没跟上，这里都会红。
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/rollback_blocked_message.dart';
import 'package:lexiloop/services/csv_import_service.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late CsvImportService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = CsvImportService(db, SettingsService(SettingsDao(db)));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 造一条纯新增批次的导入预览。
  Future<int> previewBatch(String content) async {
    final preview = await service.previewFromContent(
      content,
      filename: 'easydict.csv',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      now: now,
    );
    return preview.batchId;
  }

  /// 直接把批次改成某个状态组合。
  Future<void> setBatchState(
    int batchId, {
    required ImportBatchStatus status,
    required ImportMode importMode,
    required int existingWords,
    required bool resetLearningProgress,
  }) async {
    final query = db.update(db.importBatches)
      ..where((t) => t.id.equals(batchId));
    await query.write(
      ImportBatchesCompanion(
        status: Value(status),
        importMode: Value(importMode),
        existingWords: Value(existingWords),
        resetLearningProgress: Value(resetLearningProgress),
      ),
    );
  }

  Future<ImportBatchSummary> summaryOf(int batchId) async {
    final batches = await service.recentBatches();
    return batches.singleWhere((batch) => batch.id == batchId);
  }

  /// 服务层对当前批次的真实判定：能撤销就真撤销，不能就返回错误码。
  Future<AppErrorCode?> serviceVerdict(int batchId) async {
    try {
      await service.rollback(batchId: batchId, now: now);
      return null;
    } on AppError catch (error) {
      return error.code;
    }
  }

  group('canRollback 与服务层一致', () {
    const statuses = ImportBatchStatus.values;
    const modes = ImportMode.values;
    const existingCounts = <int>[0, 3];
    const resetFlags = <bool>[false, true];

    for (final status in statuses) {
      for (final mode in modes) {
        for (final existingWords in existingCounts) {
          for (final resetLearningProgress in resetFlags) {
            final label =
                '$status / $mode / 已有 $existingWords / '
                '重置 $resetLearningProgress';

            test(label, () async {
              final batchId = await previewBatch('单词,释义\ncat,猫\n');
              await setBatchState(
                batchId,
                status: status,
                importMode: mode,
                existingWords: existingWords,
                resetLearningProgress: resetLearningProgress,
              );

              final summary = await summaryOf(batchId);
              final verdict = await serviceVerdict(batchId);
              expect(
                verdict == null,
                summary.canRollback,
                reason: '模型说 $summary，但服务层返回 $verdict',
              );
            });
          }
        }
      }
    }
  });

  test('不存在的批次 ID 报「目标不存在」而不是静默成功', () async {
    // 静默成功是这里唯一不可接受的结局：用户点了「撤销」却什么都没发生，
    // 还会以为词条已经恢复。
    await expectLater(
      service.rollback(batchId: 9999, now: now),
      throwsA(
        isA<NotFoundError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.notFound,
        ),
      ),
    );
  });

  test('纯新增批次可撤销，撤销后词条消失', () async {
    final batchId = await previewBatch('单词,释义\ncat,猫\n');
    await service.commit(
      batchId: batchId,
      mode: ImportMode.skipExisting,
      resetLearningProgress: false,
      now: now,
    );

    final summary = await summaryOf(batchId);
    expect(summary.canRollback, isTrue);
    expect(await serviceVerdict(batchId), isNull);
    expect(await db.select(db.words).get(), isEmpty);
  });

  group('阻断原因可读', () {
    test('静态不合格时给出人话而不是错误码', () {
      const batch = ImportBatchSummary(
        id: 1,
        filename: 'a.csv',
        status: ImportBatchStatus.committed,
        importMode: ImportMode.fillMissing,
        totalRows: 1,
        validRows: 1,
        invalidRows: 0,
        duplicateRows: 0,
        createdWords: 1,
        existingWords: 0,
        queuedInitializations: 0,
        createdAt: 0,
        resetLearningProgress: false,
      );
      expect(batch.canRollback, isFalse);
      expect(staticRollbackBlockedReason(batch), contains('覆盖过已有词条'));
    });

    test('重置过学习进度的批次给出对应理由', () {
      const batch = ImportBatchSummary(
        id: 1,
        filename: 'a.csv',
        status: ImportBatchStatus.committed,
        importMode: ImportMode.skipExisting,
        totalRows: 1,
        validRows: 1,
        invalidRows: 0,
        duplicateRows: 0,
        createdWords: 0,
        existingWords: 1,
        queuedInitializations: 0,
        createdAt: 0,
        resetLearningProgress: true,
      );
      expect(staticRollbackBlockedReason(batch), contains('学习进度'));
    });

    test('可撤销的批次没有理由文案', () {
      const batch = ImportBatchSummary(
        id: 1,
        filename: 'a.csv',
        status: ImportBatchStatus.committed,
        importMode: ImportMode.skipExisting,
        totalRows: 1,
        validRows: 1,
        invalidRows: 0,
        duplicateRows: 0,
        createdWords: 1,
        existingWords: 0,
        queuedInitializations: 0,
        createdAt: 0,
        resetLearningProgress: false,
      );
      expect(staticRollbackBlockedReason(batch), isNull);
    });

    test('动态阻断把词条拼进提示', () {
      const error = ValidationError(
        AppErrorCode.importBatchHasDependencies,
        details: <String>['cotton', 'harvest'],
      );
      final message = rollbackBlockedMessage(error);
      expect(message, contains('cotton'));
      expect(message, contains('harvest'));
    });

    test('非撤销类错误退回默认文案', () {
      const error = ValidationError(AppErrorCode.csvRequired);
      expect(rollbackBlockedMessage(error), error.message);
    });
  });

  test('撤销被拒时 details 里带着挡住的词条', () async {
    final batchId = await previewBatch('单词,释义\ncat,猫\n');
    await service.commit(
      batchId: batchId,
      mode: ImportMode.skipExisting,
      resetLearningProgress: false,
      now: now,
    );
    final word = await db.select(db.words).getSingle();
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: 'answer-1',
            wordId: word.id,
            reviewedAt: now,
            rating: ReviewRating.good,
            questionType: QuestionType.enToZh,
            isCorrect: true,
            createdAt: now,
          ),
        );

    try {
      await service.rollback(batchId: batchId, now: now);
      fail('有复习日志的批次必须拒绝撤销');
    } on AppError catch (error) {
      expect(error.code, AppErrorCode.importBatchNotRollbackable);
      expect(rollbackBlockedMessage(error), contains('cat'));
    }
  });
}
