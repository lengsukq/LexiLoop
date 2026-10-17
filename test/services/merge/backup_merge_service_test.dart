/// 合并服务的数据库集成测试。
///
/// 纯合并函数已经逐条测过，这里要钉的是「接到真库上之后」的三件事：
/// 写进去的东西与预期一致；重复合并幂等；中途失败时本机一个字节都不变。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late BackupMergeService service;
  final now = DateTime(2026, 5, 1, 12).millisecondsSinceEpoch;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    service = BackupMergeService(
      BackupExporter(db),
      BackupImporter(db),
      settings,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 词条行。
  Map<String, Object?> word({
    required int id,
    required String term,
    int? updatedAt,
  }) => <String, Object?>{
    'id': id,
    'term': term,
    'normalized_term': term.toLowerCase(),
    'source_language': 'en',
    'target_language': 'zh',
    'entry_type': EntryType.word.wire,
    'content_type': LexicalContentType.word.wire,
    'initialization_status': InitializationStatus.ready.wire,
    'mastery_level': MasteryLevel.newWord.wire,
    'mastery_score': 0,
    'is_suspended': 0,
    'created_at': updatedAt ?? now,
    'updated_at': updatedAt ?? now,
  };

  /// 作答日志行。
  Map<String, Object?> log({
    required int id,
    required String answerId,
    required int wordId,
    required int reviewedAt,
    String rating = 'GOOD',
    bool isCorrect = true,
    int? sessionId,
  }) => <String, Object?>{
    'id': id,
    'client_answer_id': answerId,
    'word_id': wordId,
    'study_session_id': sessionId,
    'reviewed_at': reviewedAt,
    'rating': rating,
    'question_type': QuestionType.zhToEnSpelling.wire,
    'is_correct': isCorrect ? 1 : 0,
    'duration_ms': 3000,
    'created_at': reviewedAt,
  };

  /// 一份备份 JSON。
  String backupJson({
    List<Map<String, Object?>>? words,
    List<Map<String, Object?>>? logs,
    List<Map<String, Object?>>? sessions,
    List<Map<String, Object?>>? settingsRows,
  }) => jsonEncode(<String, Object?>{
    'format': backupFormat,
    'version': 3,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'words': ?words,
    'review_logs': ?logs,
    'study_sessions': ?sessions,
    'settings': ?settingsRows,
  });

  /// 读某个词的全部日志条数。
  Future<int> logCountOf(int wordId) async {
    final row = await db
        .customSelect(
          'SELECT count(*) AS c FROM review_logs WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// 读词条 id 与词形的映射。
  Future<Map<String, int>> wordIds() async {
    final rows = await db.customSelect('SELECT id, term FROM words').get();
    return <String, int>{
      for (final row in rows) row.read<String>('term'): row.read<int>('id'),
    };
  }

  Future<int> tableCount(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  /// 本机：apple（两条日志）+ 一份自己的设置。
  Future<void> seedLocal() async {
    await BackupImporter(db).import(
      backupJson(
        words: <Map<String, Object?>>[word(id: 1, term: 'apple')],
        logs: <Map<String, Object?>>[
          log(
            id: 1,
            answerId: 'local-1',
            wordId: 1,
            reviewedAt: now - 10 * dayMs,
          ),
          log(
            id: 2,
            answerId: 'local-2',
            wordId: 1,
            reviewedAt: now - 5 * dayMs,
          ),
        ],
        settingsRows: <Map<String, Object?>>[
          <String, Object?>{
            'key': lanSyncSettingsKey,
            'value_json': '{"deviceName":"本机","port":9100}',
            'updated_at': now - dayMs,
          },
        ],
      ),
    );
  }

  /// 对端：banana（一条日志）+ apple 的一条新日志 + 一条更旧的设置。
  String remoteJson({String bananaEntryType = 'WORD'}) => backupJson(
    words: <Map<String, Object?>>[
      word(id: 1, term: 'banana'),
      word(id: 2, term: 'apple'),
    ],
    logs: <Map<String, Object?>>[
      log(id: 1, answerId: 'remote-1', wordId: 1, reviewedAt: now - dayMs),
      log(id: 2, answerId: 'remote-2', wordId: 2, reviewedAt: now),
    ],
    settingsRows: <Map<String, Object?>>[
      <String, Object?>{
        'key': 'aiRetryCount',
        'value_json': '3',
        'updated_at': now,
      },
      <String, Object?>{
        'key': lanSyncSettingsKey,
        'value_json': '{"deviceName":"对端","port":8765}',
        'updated_at': now + dayMs,
      },
    ],
  );

  group('成功合并', () {
    setUp(seedLocal);

    test('对端的词条与作答进来，本机的一条不少', () async {
      final outcome = await service.merge(remoteJson());

      expect(outcome.counts.addedWords, 1);
      expect(outcome.counts.addedLogs, 2);
      final ids = await wordIds();
      expect(ids.keys.toSet(), <String>{'apple', 'banana'});
      expect(await tableCount('review_logs'), 4);
      // apple 的本地两条都还在。
      expect(await logCountOf(ids['apple']!), 3, reason: '本地 2 条 + 远端 1 条');
      expect(await logCountOf(ids['banana']!), 1);
    });

    test('统计表按合并后的日志重算', () async {
      await service.merge(remoteJson());
      final ids = await wordIds();
      final row = await db
          .customSelect(
            'SELECT total_reviews FROM word_review_stats WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(ids['apple'])],
          )
          .getSingle();
      expect(row.read<int>('total_reviews'), 3);
    });

    test('卡片按合并后的流水重放', () async {
      await service.merge(remoteJson());
      final ids = await wordIds();
      final row = await db
          .customSelect(
            'SELECT reps, last_review_at FROM review_cards WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(ids['apple'])],
          )
          .getSingle();
      expect(row.read<int>('reps'), 3);
      expect(row.read<int?>('last_review_at'), now);
    });

    test('排除的设置键保持本机值', () async {
      await service.merge(remoteJson());
      final stored = await LanSyncStateStoreProbe.read(db, lanSyncSettingsKey);
      expect(stored, contains('"deviceName":"本机"'));
    });

    test('非排除的设置键跟着对端走', () async {
      await service.merge(remoteJson());
      final stored = await LanSyncStateStoreProbe.read(db, 'aiRetryCount');
      expect(stored, '3');
    });

    test('本机专属表没有被清空', () async {
      // 先造一条导入批次（模拟本机的操作历史）。
      await db
          .into(db.importBatches)
          .insert(
            ImportBatchesCompanion.insert(
              filename: 'history.csv',
              importMode: ImportMode.skipExisting,
              createdAt: now,
            ),
          );
      await service.merge(remoteJson());
      expect(await tableCount('import_batches'), 1);
    });
  });

  group('幂等', () {
    setUp(seedLocal);

    test('同一份对端合并两次，第二次不新增任何行', () async {
      final first = await service.merge(remoteJson());
      final wordsAfterFirst = await tableCount('words');
      final logsAfterFirst = await tableCount('review_logs');

      final second = await service.merge(remoteJson());

      expect(first.counts.addedWords, 1);
      expect(second.counts.addedWords, isZero);
      expect(second.counts.addedLogs, isZero);
      expect(second.counts.rebuiltWords, isZero);
      expect(await tableCount('words'), wordsAfterFirst);
      expect(await tableCount('review_logs'), logsAfterFirst);
    });
  });

  group('失败时本机不变', () {
    setUp(seedLocal);

    test('产物里有非法枚举时整体回滚', () async {
      // 对端的 banana 带着一个不存在的 entry_type：解析能过，
      // 写库时的枚举校验会拒绝——于是整个事务回滚。
      final broken = backupJson(
        words: <Map<String, Object?>>[
          <String, Object?>{
            ...word(id: 1, term: 'banana'),
            'entry_type': 'NOT_A_TYPE',
          },
        ],
        logs: <Map<String, Object?>>[
          log(id: 1, answerId: 'remote-1', wordId: 1, reviewedAt: now),
        ],
      );

      await expectLater(
        service.merge(broken),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidFormat,
          ),
        ),
      );

      final ids = await wordIds();
      expect(ids.keys.toSet(), <String>{'apple'}, reason: 'banana 不该留下');
      expect(await tableCount('review_logs'), 2);
    });

    test('负载非法时一个事务都不开', () async {
      await expectLater(
        service.merge('{ not json'),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidJson,
          ),
        ),
      );
      final ids = await wordIds();
      expect(ids.keys.toSet(), <String>{'apple'});
    });
  });

  group('边界', () {
    test('本机是空库时，合并等于一次完整导入', () async {
      final outcome = await service.merge(remoteJson());
      expect(outcome.counts.addedWords, 2);
      final ids = await wordIds();
      expect(ids.keys.toSet(), <String>{'apple', 'banana'});
    });

    test('对端是空备份时，本机完全不变', () async {
      await seedLocal();
      final outcome = await service.merge(backupJson());
      expect(outcome.counts.addedWords, isZero);
      final ids = await wordIds();
      expect(ids.keys.toSet(), <String>{'apple'});
      expect(await tableCount('review_logs'), 2);
    });
  });
}

/// 直接读 `settings` 表的一个键。
///
/// 服务层没有「读单键」的公开入口（`SettingsService.load()` 返回类型化视图，
/// 测试里要的是原始值），因此这里用一条最小的 SQL 探针。
abstract final class LanSyncStateStoreProbe {
  /// 读 `settings.value_json`；不存在时返回 `null`。
  static Future<String?> read(AppDatabase db, String key) async {
    final row = await db
        .customSelect(
          'SELECT value_json FROM settings WHERE key = ?',
          variables: <Variable<Object>>[Variable<String>(key)],
        )
        .getSingleOrNull();
    return row?.read<String>('value_json');
  }
}
