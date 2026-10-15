/// 备份导出测试。
///
/// 核心验收点是**往返保真**：`export(db)` 之后导入回去，12 张表的每一行都必须
/// 与导出前逐列相同。其余用例分别钉住信封形状、枚举与 null 的序列化形态、
/// 刻意排除的两张表，以及与导入端共用的大小上限。
///
/// 真实 27MB 备份的用例由 `LEXILOOP_BACKUP_PATH` 开启，缺省跳过。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  late AppDatabase db;
  late BackupExporter exporter;
  late BackupImporter importer;

  final now = DateTime(2026, 10, 14, 22, 27).millisecondsSinceEpoch;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    exporter = BackupExporter(db);
    importer = BackupImporter(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 按主键顺序读出某张表的全部行，供往返比对。
  Future<List<Map<String, Object?>>> snapshot(String table) async {
    final rows = await db
        .customSelect('SELECT * FROM $table ORDER BY rowid')
        .get();
    return rows.map((row) => row.data).toList(growable: false);
  }

  /// 12 张表整体快照。
  Future<Map<String, List<Map<String, Object?>>>> snapshotAll() async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final table in BackupImporter.tableOrder) {
      result[table] = await snapshot(table);
    }
    return result;
  }

  /// 塞一张覆盖全部 12 张表、且外键自洽的小型数据集。
  Future<void> seedFullDatabase() async {
    await _insertWords(db, now);
    await _insertContents(db, now);
    await _insertSessions(db, now);
    await _insertItems(db, now);
    await _insertCards(db, now);
    await _insertReviewLogs(db, now);
    await _insertWrongStates(db, now);
    await _insertImportBatches(db, now);
    await _insertImportRows(db, now);
    await _insertJobs(db, now);
    await _insertAttempts(db, now);
    await _insertSettings(db, now);
    await db
        .into(db.gameHighScores)
        .insert(
          GameHighScoresCompanion.insert(
            gameMode: 'GAME_WORD_BUILDER',
            score: 999,
            maxCombo: const Value(9),
            accuracy: const Value(1),
            playedAt: now,
            createdAt: now,
          ),
        );
  }

  group('信封', () {
    test('包含 format / version / database / exportedAt 与 12 张表', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      final decoded = jsonDecode(raw) as Map<String, Object?>;

      expect(decoded['format'], backupFormat);
      expect(decoded['version'], isA<num>());
      expect(decoded['database'], backupDatabaseFlavor);
      expect(decoded['exportedAt'], isA<String>());
      for (final table in BackupImporter.tableOrder) {
        expect(decoded[table], isA<List<Object?>>(), reason: '缺少表 $table');
      }
    });

    test('表顺序即导入端的父表优先顺序', () {
      expect(BackupExporter.tableOrder, BackupImporter.tableOrder);
      expect(
        BackupExporter.tableOrder.indexOf('words'),
        lessThan(BackupExporter.tableOrder.indexOf('review_logs')),
      );
    });

    test('导出的字节一定能被导入端读回', () async {
      await seedFullDatabase();
      final exported = await exporter.exportToJson();
      await expectLater(
        importer.import(utf8.decode(exported.bytes)),
        completes,
      );
    });
  });

  group('往返保真', () {
    test('导出 → 清空 → 导入后 12 张表逐列相同', () async {
      await seedFullDatabase();
      final before = await snapshotAll();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);

      await importer.import(raw);
      final after = await snapshotAll();

      for (final table in BackupImporter.tableOrder) {
        expect(
          _normalize(after[table]!),
          equals(_normalize(before[table]!)),
          reason: '表 $table 往返后不一致',
        );
      }
    });

    test('往返两次得到同一份备份字节（导出是幂等的）', () async {
      await seedFullDatabase();
      final first = await exporter.exportToJson();
      final before = await snapshotAll();

      await importer.import(utf8.decode(first.bytes));
      final second = await exporter.exportToJson();
      final after = await snapshotAll();

      // exportedAt 会变，比较时把它抹掉。
      expect(
        _stripExportedAt(utf8.decode(second.bytes)),
        _stripExportedAt(utf8.decode(first.bytes)),
      );
      expect(_normalizeAll(after), _normalizeAll(before));
    });

    test('浮点列（如 FSRS stability）不丢精度', () async {
      await seedFullDatabase();
      final before = (await snapshot('review_cards')).single['stability'];
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      await importer.import(raw);

      final card = await db.select(db.reviewCards).getSingle();
      expect(card.stability, before);
    });
  });

  group('值的序列化形态', () {
    test('枚举列写出 wire 字符串而不是序号', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final word =
          (decoded['words']! as List<Object?>).first! as Map<String, Object?>;

      expect(word['entry_type'], 'WORD');
      expect(word['content_type'], 'WORD');
      expect(word['initialization_status'], 'READY');
      expect(word['mastery_level'], 'FAMILIAR');

      final item =
          (decoded['study_session_items']! as List<Object?>).first!
              as Map<String, Object?>;
      expect(item['status'], 'ANSWERED');
      expect(item['task_type'], 'NEW');
    });

    test('时间戳保持 epoch 毫秒整数', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final word =
          (decoded['words']! as List<Object?>).first! as Map<String, Object?>;

      expect(word['created_at'], isA<int>());
      expect(word['created_at'], now);
    });

    test('空值保持 null 而不是被丢掉或变成空串', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final session =
          (decoded['study_sessions']! as List<Object?>).first!
              as Map<String, Object?>;

      expect(session.containsKey('completed_at'), isTrue);
      expect(session['completed_at'], isNull);

      final log =
          (decoded['review_logs']! as List<Object?>).first!
              as Map<String, Object?>;
      expect(log['study_session_item_id'], isNull);
      expect(log['duration_ms'], isNull);
    });

    test('布尔列以 0 / 1 落库，导入后读回仍是布尔', () async {
      await seedFullDatabase();
      await importer.import(utf8.decode((await exporter.exportToJson()).bytes));

      final word = await db.select(db.words).getSingle();
      expect(word.isSuspended, isFalse);
    });
  });

  group('刻意不导出的表', () {
    test('game_high_scores 与 word_review_stats 不出现在文件里', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);
      final decoded = jsonDecode(raw) as Map<String, Object?>;

      for (final table in tablesExcludedFromExport) {
        expect(decoded.containsKey(table), isFalse, reason: '$table 不该被导出');
        expect(BackupImporter.tableOrder.contains(table), isFalse);
      }
      expect(tablesExcludedFromExport, <String>[
        'game_high_scores',
        'word_review_stats',
      ]);
    });

    test('排行榜分数不随备份回到新库', () async {
      await seedFullDatabase();
      final raw = utf8.decode((await exporter.exportToJson()).bytes);

      // 换一个空库导入，新计分公式从空表起步。
      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      await BackupImporter(fresh).import(raw);

      final scores = await fresh
          .customSelect('SELECT count(*) AS c FROM game_high_scores')
          .getSingle();
      final stats = await fresh
          .customSelect('SELECT count(*) AS c FROM word_review_stats')
          .getSingle();
      expect(scores.read<int>('c'), 0);
      expect(
        stats.read<int>('c'),
        greaterThan(0),
        reason: 'word_review_stats 仍由 review_logs 重算，不来自备份',
      );
    });
  });

  group('大小上限', () {
    test('超过上限时抛出与导入端相同的错误码', () async {
      // 用一条超长设置值把库撑过上限：JSON 编码后仍大于 maxBackupBytes。
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'oversized',
              valueJson: 'x' * (maxBackupBytes + 1),
              updatedAt: now,
            ),
          );

      await expectLater(
        exporter.exportToJson(),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupTooLarge,
          ),
        ),
      );
    });

    test('导出与导入共用同一个上限常量', () {
      expect(maxBackupBytes, 100 * 1024 * 1024);
    });
  });

  group('真实备份', () {
    test('27MB 真实备份可导入 → 导出 → 再导入', () async {
      final path = Platform.environment['LEXILOOP_BACKUP_PATH'];
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('未设置 LEXILOOP_BACKUP_PATH，跳过真实备份验证');
        return;
      }

      final raw = File(path).readAsStringSync();
      final imported = await importer.import(raw);
      expect(imported.rowCounts['words'], greaterThan(0));

      final exported = await exporter.exportToJson();
      expect(exported.totalRows, greaterThan(0));
      expect(
        exported.bytes.length,
        lessThanOrEqualTo(maxBackupBytes),
        reason: '真实备份必须落在上限内',
      );

      // 再导回去，行数必须一致。
      final fresh = AppDatabase(NativeDatabase.memory());
      addTearDown(fresh.close);
      final round = await BackupImporter(fresh)
          .import(utf8.decode(exported.bytes));
      for (final table in BackupImporter.tableOrder) {
        expect(
          round.rowCounts[table],
          imported.rowCounts[table],
          reason: table,
        );
      }
    });
  });
}

/// 归一化行里的数值，便于逐列比对。
///
/// SQLite 的 REAL 列在某些路径上读回的是整数值（`0` 而非 `0.0`），
/// 导出再导入之后同一列可能换个类型出现。两者在库里等价，比对时不应算差异，
/// 因此把「数值上为整数」的双精度一律压成整数。
List<Map<String, Object?>> _normalize(List<Map<String, Object?>> rows) {
  return rows
      .map(
        (row) => <String, Object?>{
          for (final entry in row.entries) entry.key: _canonical(entry.value),
        },
      )
      .toList(growable: false);
}

Map<String, List<Map<String, Object?>>> _normalizeAll(
  Map<String, List<Map<String, Object?>>> snapshot,
) {
  return <String, List<Map<String, Object?>>>{
    for (final entry in snapshot.entries) entry.key: _normalize(entry.value),
  };
}

Object? _canonical(Object? value) {
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value;
}

/// 抹掉信封里的 `exportedAt`，让两次导出可比。
String _stripExportedAt(String raw) =>
    raw.replaceFirst(RegExp('"exportedAt":"[^"]*"'), '"exportedAt":"X"');

// ── 数据填充 ──

Future<void> _insertWords(AppDatabase db, int now) async {
  await db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: 'cotton',
          normalizedTerm: 'cotton',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          sourceLanguageName: const Value('英语'),
          entryType: EntryType.word,
          contentType: const Value(LexicalContentType.word),
          initializationStatus: const Value(InitializationStatus.ready),
          masteryLevel: const Value(MasteryLevel.familiar),
          masteryScore: const Value(55),
          isSuspended: const Value(false),
          userNote: const Value('做笔记用'),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertContents(AppDatabase db, int now) async {
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.wordContents)
      .insert(
        WordContentsCompanion.insert(
          wordId: Value<int>(word.id),
          definitionsJson: const Value('[{"text":"棉花"}]'),
          examplesJson: const Value('[]'),
          contentSource: const Value(ContentSource.dictionaryOnly),
          contentVersion: const Value(3),
          initializedAt: Value(now),
          updatedAt: now,
        ),
      );
}

Future<void> _insertSessions(AppDatabase db, int now) async {
  await db
      .into(db.studySessions)
      .insert(
        StudySessionsCompanion.insert(
          sessionType: StudyMode.daily,
          sourceType: const Value(null),
          startedAt: now,
          createdAt: now,
        ),
      );
}

Future<void> _insertItems(AppDatabase db, int now) async {
  final session = await db.select(db.studySessions).getSingle();
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.studySessionItems)
      .insert(
        StudySessionItemsCompanion.insert(
          studySessionId: session.id,
          position: 0,
          wordId: word.id,
          taskType: StudyTaskType.newWord,
          questionType: QuestionType.enToZh,
          status: const Value(StudyItemStatus.answered),
          answeredAt: Value(now),
          createdAt: now,
        ),
      );
}

Future<void> _insertCards(AppDatabase db, int now) async {
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.reviewCards)
      .insert(
        ReviewCardsCompanion.insert(
          wordId: Value<int>(word.id),
          dueAt: now,
          stability: 12.5,
          difficulty: 4.2,
          elapsedDays: 3,
          scheduledDays: 12,
          reps: 5,
          lapses: 1,
          fsrsState: 2,
          lastReviewAt: Value(now),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertReviewLogs(AppDatabase db, int now) async {
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          clientAnswerId: 'answer-1',
          wordId: word.id,
          studySessionId: const Value(null),
          studySessionItemId: const Value(null),
          reviewedAt: now,
          rating: ReviewRating.good,
          questionType: QuestionType.enToZh,
          isCorrect: true,
          durationMs: const Value(null),
          cardBeforeJson: const Value('{"stability":1.0}'),
          createdAt: now,
        ),
      );
}

Future<void> _insertWrongStates(AppDatabase db, int now) async {
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.wrongWordStates)
      .insert(
        WrongWordStatesCompanion.insert(
          wordId: Value<int>(word.id),
          active: const Value(true),
          wrongCount: const Value(2),
          hardCount: const Value(1),
          consecutiveCorrect: const Value(0),
          lastWrongAt: Value(now),
          updatedAt: now,
        ),
      );
}

Future<void> _insertImportBatches(AppDatabase db, int now) async {
  await db
      .into(db.importBatches)
      .insert(
        ImportBatchesCompanion.insert(
          filename: 'easydict.csv',
          fileHash: const Value(null),
          importMode: ImportMode.fillMissing,
          resetLearningProgress: const Value(true),
          totalRows: const Value(3),
          validRows: const Value(2),
          createdWords: const Value(1),
          existingWords: const Value(1),
          queuedInitializations: const Value(1),
          status: const Value(ImportBatchStatus.committed),
          createdAt: now,
          completedAt: Value(now),
        ),
      );
}

Future<void> _insertImportRows(AppDatabase db, int now) async {
  final batch = await db.select(db.importBatches).getSingle();
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.importRows)
      .insert(
        ImportRowsCompanion.insert(
          importBatchId: batch.id,
          rowNumber: 2,
          rawJson: const Value('{"term":"cotton"}'),
          normalizedTerm: const Value('cotton'),
          wordId: Value<int>(word.id),
          status: ImportRowStatus.existing,
          errorCode: const Value(null),
          errorMessage: const Value(null),
          metadataJson: const Value(null),
          createdAt: now,
        ),
      );
}

Future<void> _insertJobs(AppDatabase db, int now) async {
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.initializationJobs)
      .insert(
        InitializationJobsCompanion.insert(
          wordId: word.id,
          mode: InitializationMode.fillMissingFields,
          requestedFieldsJson: const Value('["definitions"]'),
          status: const Value(InitializationStatus.running),
          priority: const Value(10),
          maxAttempts: const Value(3),
          availableAt: Value(now),
          lockedAt: Value(now),
          lockedBy: const Value('worker-1'),
          lastError: const Value('timeout'),
          lastErrorCode: const Value('PROVIDER_TRANSIENT_FAILURE'),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertAttempts(AppDatabase db, int now) async {
  final job = await db.select(db.initializationJobs).getSingle();
  final word = await db.select(db.words).getSingle();
  await db
      .into(db.providerAttempts)
      .insert(
        ProviderAttemptsCompanion.insert(
          initializationJobId: Value<int>(job.id),
          wordId: word.id,
          providerId: 'dictionaryapi.dev',
          status: ProviderAttemptStatus.failed,
          durationMs: const Value(3575),
          fieldsReturnedJson: const Value('["definitions"]'),
          errorCode: const Value('PROVIDER_TRANSIENT_FAILURE'),
          errorMessage: const Value('boom'),
          metadataJson: const Value(null),
          createdAt: now,
        ),
      );
}

Future<void> _insertSettings(AppDatabase db, int now) async {
  await db
      .into(db.settings)
      .insert(
        SettingsCompanion.insert(
          key: 'llmConfig',
          valueJson: '{"providers":[]}',
          updatedAt: now,
        ),
      );
}
