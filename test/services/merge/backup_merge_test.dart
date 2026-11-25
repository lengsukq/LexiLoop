/// 纯合并函数的测试。
///
/// 这里不碰数据库：合并的难点全在「这两个 id 是不是同一个东西」「哪边的
/// 元数据更新」「哪些词的派生状态该重算」，用行数据直接断言最清楚，
/// 也最快。落库那一层由 `backup_merge_service_test.dart` 负责。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/features/settings/providers_section.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/merge/backup_merge.dart';

/// 合并时间的基准。
const int now = 1800000000000;

/// 一天。
const int day = dayMs;

/// 造一份 12 张表的空壳。
Map<String, List<Map<String, Object?>>> emptyTables() =>
    <String, List<Map<String, Object?>>>{
      for (final table in BackupImporter.tableOrder)
        table: <Map<String, Object?>>[],
    };

/// 一条 `words` 行。
Map<String, Object?> wordRow({
  required int id,
  required String term,
  int updatedAt = now,
  int masteryScore = 0,
  MasteryLevel masteryLevel = MasteryLevel.newWord,
  InitializationStatus initializationStatus = InitializationStatus.ready,
  String? userNote,
  bool isSuspended = false,
}) => <String, Object?>{
  'id': id,
  'term': term,
  'normalized_term': term.toLowerCase(),
  'source_language': 'en',
  'target_language': 'zh',
  'entry_type': EntryType.word.wire,
  'content_type': LexicalContentType.word.wire,
  'initialization_status': initializationStatus.wire,
  'mastery_level': masteryLevel.wire,
  'mastery_score': masteryScore,
  'is_suspended': isSuspended ? 1 : 0,
  'user_note': userNote,
  'created_at': updatedAt,
  'updated_at': updatedAt,
};

/// 一条 `word_contents` 行。
Map<String, Object?> contentRow({
  required int wordId,
  required String definitions,
  int updatedAt = now,
}) => <String, Object?>{
  'word_id': wordId,
  'definitions_json': definitions,
  'updated_at': updatedAt,
};

/// 一条 `review_logs` 行。
Map<String, Object?> logRow({
  required int id,
  required String answerId,
  required int wordId,
  required int reviewedAt,
  String rating = 'GOOD',
  bool isCorrect = true,
  int? durationMs = 3000,
  int? sessionId,
  int? itemId,
}) => <String, Object?>{
  'id': id,
  'client_answer_id': answerId,
  'word_id': wordId,
  'study_session_id': sessionId,
  'study_session_item_id': itemId,
  'reviewed_at': reviewedAt,
  'rating': rating,
  'question_type': QuestionType.zhToEnSpelling.wire,
  'is_correct': isCorrect ? 1 : 0,
  'duration_ms': durationMs,
  'created_at': reviewedAt,
};

/// 一条 `study_sessions` 行。
Map<String, Object?> sessionRow({
  required int id,
  required int startedAt,
  String type = 'DAILY',
  String? sourceType,
}) => <String, Object?>{
  'id': id,
  'session_type': type,
  'source_type': sourceType,
  'started_at': startedAt,
  'created_at': startedAt,
  'planned_count': 1,
  'completed_count': 1,
};

/// 一条 `study_session_items` 行。
Map<String, Object?> itemRow({
  required int id,
  required int sessionId,
  required int wordId,
  required double position,
  String status = 'ANSWERED',
}) => <String, Object?>{
  'id': id,
  'study_session_id': sessionId,
  'position': position,
  'word_id': wordId,
  'task_type': StudyTaskType.review.wire,
  'question_type': QuestionType.zhToEnSpelling.wire,
  'status': status,
  'created_at': now,
};

/// 一条 `review_cards` 行。
Map<String, Object?> cardRow({
  required int wordId,
  int dueAt = now,
  int reps = 3,
  double stability = 10,
  int updatedAt = now,
}) => <String, Object?>{
  'word_id': wordId,
  'due_at': dueAt,
  'stability': stability,
  'difficulty': 5.0,
  'elapsed_days': 1,
  'scheduled_days': 3,
  'reps': reps,
  'lapses': 0,
  'fsrs_state': 2,
  'learning_steps': 0,
  'last_review_at': now - day,
  'created_at': now - day,
  'updated_at': updatedAt,
};

/// 一条 `wrong_word_states` 行。
Map<String, Object?> wrongRow({required int wordId, int updatedAt = now}) =>
    <String, Object?>{
      'word_id': wordId,
      'active': 1,
      'wrong_count': 2,
      'hard_count': 0,
      'consecutive_correct': 0,
      'last_wrong_at': now,
      'last_correct_at': null,
      'resolved_at': null,
      'updated_at': updatedAt,
    };

/// 一条 `settings` 行。
Map<String, Object?> settingRow({
  required String key,
  required String value,
  int updatedAt = now,
}) => <String, Object?>{
  'key': key,
  'value_json': value,
  'updated_at': updatedAt,
};

void main() {
  late FsrsScheduler scheduler;

  setUp(() {
    scheduler = FsrsScheduler();
  });

  MergeOutcome merge(
    Map<String, List<Map<String, Object?>>> local,
    Map<String, List<Map<String, Object?>>> remote,
  ) => mergeBackupTables(
    local: local,
    remote: remote,
    scheduler: scheduler,
    now: now,
  );

  group('产物完整性', () {
    test('产物覆盖 tableOrder 里的每一张表（漏一张就等于删了那张的数据）', () {
      final outcome = merge(emptyTables(), emptyTables());
      expect(outcome.tables.keys.toSet(), BackupImporter.tableOrder.toSet());
    });

    test('本机专属表原样带走', () {
      final local = emptyTables()
        ..['import_batches'] = <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'filename': 'a.csv', 'created_at': now},
        ]
        ..['initialization_jobs'] = <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'word_id': 1, 'created_at': now},
        ];
      final remote = emptyTables()
        ..['import_batches'] = <Map<String, Object?>>[
          <String, Object?>{
            'id': 9,
            'filename': 'remote.csv',
            'created_at': now,
          },
        ];

      final outcome = merge(local, remote);

      expect(outcome.tables['import_batches'], hasLength(1));
      expect(outcome.tables['import_batches']!.single['filename'], 'a.csv');
      expect(outcome.tables['initialization_jobs'], hasLength(1));
    });

    test('两边都空时什么都不变', () {
      final outcome = merge(emptyTables(), emptyTables());
      expect(outcome.counts.addedWords, isZero);
      expect(outcome.counts.addedLogs, isZero);
      for (final table in BackupImporter.tableOrder) {
        expect(outcome.tables[table], isEmpty, reason: table);
      }
    });
  });

  group('词条', () {
    test('身份不存在的远端词条被插入，并拿到本地的新 id', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'banana')];

      final outcome = merge(local, remote);

      expect(outcome.counts.addedWords, 1);
      final added = outcome.tables['words']!.firstWhere(
        (row) => row['normalized_term'] == 'banana',
      );
      // 本地最大 id 是 7，因此新词从 8 开始——**不**沿用远端的 1，
      // 否则会撞上本地主键。
      expect(added['id'], 8);
    });

    test('身份相同的远端词条被映射到本地 id，不新增行', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'Apple')];

      final outcome = merge(local, remote);

      expect(outcome.tables['words'], hasLength(1));
      expect(outcome.counts.addedWords, isZero);
    });

    test('远端更新：可合并的列跟着走，派生列与身份列不动', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[
          wordRow(
            id: 7,
            term: 'apple',
            updatedAt: now - day,
            masteryScore: 42,
            masteryLevel: MasteryLevel.familiar,
            userNote: '本地笔记',
          ),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[
          wordRow(
            id: 1,
            term: 'apple',
            masteryScore: 99,
            masteryLevel: MasteryLevel.mastered,
            userNote: '远端笔记',
            isSuspended: true,
          ),
        ];

      final outcome = merge(local, remote);
      final row = outcome.tables['words']!.single;

      expect(outcome.counts.updatedWords, 1);
      expect(row['user_note'], '远端笔记');
      expect(row['is_suspended'], 1);
      expect(row['id'], 7, reason: '本地 id 不能被远端覆盖');
      // 没有新作答 → 不重放 → 熟练度保持本机值，绝不取远端。
      expect(row['mastery_score'], 42);
      expect(row['mastery_level'], MasteryLevel.familiar.wire);
    });

    test('已有词条保留本机初始化状态，包括排队与已完成状态', () {
      for (final status in <InitializationStatus>[
        InitializationStatus.queued,
        InitializationStatus.ready,
        InitializationStatus.partial,
      ]) {
        final local = emptyTables()
          ..['words'] = <Map<String, Object?>>[
            wordRow(id: 7, term: 'apple', initializationStatus: status),
          ];
        final remote = emptyTables()
          ..['words'] = <Map<String, Object?>>[
            wordRow(
              id: 1,
              term: 'apple',
              updatedAt: now + day,
              initializationStatus: InitializationStatus.running,
            ),
          ];

        final outcome = merge(local, remote);

        expect(
          outcome.tables['words']!.single['initialization_status'],
          status.wire,
          reason: '远端 RUNNING 不应覆盖本机 ${status.wire}',
        );
      }
    });

    test('新远端词条的 QUEUED 与 RUNNING 归一化为 PENDING', () {
      for (final status in <InitializationStatus>[
        InitializationStatus.queued,
        InitializationStatus.running,
      ]) {
        final remote = emptyTables()
          ..['words'] = <Map<String, Object?>>[
            wordRow(id: 1, term: 'apple', initializationStatus: status),
          ];

        final outcome = merge(emptyTables(), remote);

        expect(
          outcome.tables['words']!.single['initialization_status'],
          InitializationStatus.pending.wire,
          reason: '远端 ${status.wire} 对应的设备本地任务不会被导入',
        );
      }
    });

    test('本机更新时不覆盖', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[
          wordRow(id: 7, term: 'apple', userNote: '本地笔记'),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[
          wordRow(id: 1, term: 'apple', updatedAt: now - day, userNote: '旧笔记'),
        ];

      final outcome = merge(local, remote);
      expect(outcome.tables['words']!.single['user_note'], '本地笔记');
      expect(outcome.counts.updatedWords, isZero);
    });
  });

  group('词典内容', () {
    test('按映射后的 word_id 整行取新', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')]
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 7, definitions: '旧释义', updatedAt: now - day),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 1, definitions: '新释义'),
        ];

      final outcome = merge(local, remote);

      expect(outcome.tables['word_contents'], hasLength(1));
      final row = outcome.tables['word_contents']!.single;
      expect(row['definitions_json'], '新释义');
      expect(row['word_id'], 7);
    });

    test('本机更新时保留本机的', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')]
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 7, definitions: '本机'),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 1, definitions: '远端', updatedAt: now - day),
        ];

      final outcome = merge(local, remote);
      expect(outcome.tables['word_contents']!.single['definitions_json'], '本机');
    });

    test('内容对应的词没合进来时跳过（防御）', () {
      final remote = emptyTables()
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 404, definitions: '孤儿'),
        ];

      final outcome = merge(emptyTables(), remote);
      expect(outcome.tables['word_contents'], isEmpty);
    });
  });

  group('作答流水', () {
    test('按 client_answer_id 去重取并集', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now - day),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 5, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          // 同一条（本机已经有）
          logRow(id: 1, answerId: 'a-1', wordId: 5, reviewedAt: now - day),
          // 新的
          logRow(id: 2, answerId: 'a-2', wordId: 5, reviewedAt: now),
        ];

      final outcome = merge(local, remote);

      expect(outcome.counts.addedLogs, 1);
      expect(outcome.tables['review_logs'], hasLength(2));
      final added = outcome.tables['review_logs']!.firstWhere(
        (row) => row['client_answer_id'] == 'a-2',
      );
      // 远端词 id 5 映射到本地词 id 1。
      expect(added['word_id'], 1);
      // 新日志拿到本地的新 id，而不是远端的 2。
      expect(added['id'], 2);
    });

    test('远端日志的词条映射不上时丢弃并计数', () {
      final remote = emptyTables()
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'orphan', wordId: 404, reviewedAt: now),
        ];

      final outcome = merge(emptyTables(), remote);

      expect(outcome.tables['review_logs'], isEmpty);
      expect(outcome.counts.droppedLogs, 1);
    });
  });

  group('会话与题目', () {
    test('新会话连它的题目一起插入，题目 id 与 word_id 都重映射', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['study_sessions'] = <Map<String, Object?>>[
          sessionRow(id: 1, startedAt: now),
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          itemRow(id: 1, sessionId: 1, wordId: 1, position: 0),
        ]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(
            id: 1,
            answerId: 'a-1',
            wordId: 1,
            reviewedAt: now,
            sessionId: 1,
            itemId: 1,
          ),
        ];

      final outcome = merge(local, remote);

      expect(outcome.counts.addedSessions, 1);
      final session = outcome.tables['study_sessions']!.single;
      final item = outcome.tables['study_session_items']!.single;
      final log = outcome.tables['review_logs']!.single;

      expect(session['id'], 1);
      expect(item['study_session_id'], session['id']);
      expect(item['word_id'], 7);
      expect(log['study_session_id'], session['id']);
      expect(log['study_session_item_id'], item['id']);
    });

    test('身份相同的会话不重复插入，其题目也不重复', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')]
        ..['study_sessions'] = <Map<String, Object?>>[
          sessionRow(id: 3, startedAt: now),
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          itemRow(id: 4, sessionId: 3, wordId: 7, position: 0),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['study_sessions'] = <Map<String, Object?>>[
          sessionRow(id: 1, startedAt: now),
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          itemRow(id: 1, sessionId: 1, wordId: 1, position: 0),
        ]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(
            id: 1,
            answerId: 'a-1',
            wordId: 1,
            reviewedAt: now,
            sessionId: 1,
            itemId: 1,
          ),
        ];

      final outcome = merge(local, remote);

      expect(outcome.tables['study_sessions'], hasLength(1));
      expect(outcome.tables['study_session_items'], hasLength(1));
      // 同一场会话按 position 对齐题目，日志里的题目引用能保留映射到本机题目 id。
      expect(outcome.tables['review_logs']!.single['study_session_id'], 3);
      expect(outcome.tables['review_logs']!.single['study_session_item_id'], 4);
    });

    test('进行中的本地会话在远端完成后，合并会推进会话与题目状态', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 7, term: 'apple')]
        ..['study_sessions'] = <Map<String, Object?>>[
          <String, Object?>{
            ...sessionRow(id: 3, startedAt: now),
            'completed_at': null,
            'completed_count': 0,
          },
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          <String, Object?>{
            ...itemRow(id: 4, sessionId: 3, wordId: 7, position: 0),
            'status': StudyItemStatus.pending.wire,
            'answered_at': null,
          },
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['study_sessions'] = <Map<String, Object?>>[
          <String, Object?>{
            ...sessionRow(id: 1, startedAt: now),
            'completed_at': now + 60000,
            'completed_count': 1,
          },
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          <String, Object?>{
            ...itemRow(id: 1, sessionId: 1, wordId: 1, position: 0),
            'status': StudyItemStatus.answered.wire,
            'answered_at': now + 30000,
          },
        ];

      final outcome = merge(local, remote);

      final mergedSession = outcome.tables['study_sessions']!.single;
      final mergedItem = outcome.tables['study_session_items']!.single;
      expect(mergedSession['completed_at'], now + 60000);
      expect(mergedSession['completed_count'], 1);
      expect(mergedItem['status'], StudyItemStatus.answered.wire);
      expect(mergedItem['answered_at'], now + 30000);
    });
  });

  group('派生状态只重算受影响的词', () {
    test('没收到新作答的词，卡片与错词行原样不动', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[
          wordRow(id: 1, term: 'apple'),
          wordRow(id: 2, term: 'banana'),
        ]
        ..['review_cards'] = <Map<String, Object?>>[
          cardRow(wordId: 1, dueAt: 111, reps: 1),
          cardRow(wordId: 2, dueAt: 222, reps: 9),
        ]
        ..['wrong_word_states'] = <Map<String, Object?>>[
          wrongRow(wordId: 2, updatedAt: 12345),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'banana')]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now),
        ];

      final outcome = merge(local, remote);

      // banana 收到了新作答、被重算；apple 没有，卡片必须逐字段不变。
      final appleCard = outcome.tables['review_cards']!.firstWhere(
        (row) => row['word_id'] == 1,
      );
      expect(appleCard['due_at'], 111);
      expect(appleCard['reps'], 1);

      final bananaCard = outcome.tables['review_cards']!.firstWhere(
        (row) => row['word_id'] == 2,
      );
      expect(bananaCard['reps'], 1, reason: '只有一条流水，重放后 reps = 1');
      expect(bananaCard['due_at'], isNot(222));
    });

    test('两边各推进一半的流水：卡片按合并后的时间顺序重放', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now - 10 * day),
        ];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-2', wordId: 1, reviewedAt: now - 5 * day),
        ];

      final outcome = merge(local, remote);

      expect(outcome.counts.rebuiltWords, 1);
      final card = outcome.tables['review_cards']!.single;
      expect(card['reps'], 2, reason: '两条流水各推进一次');
      expect(card['last_review_at'], now - 5 * day, reason: '按时间取最后一条');
    });

    test('重放没有产生错词记录时，旧的错词行被清掉', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['wrong_word_states'] = <Map<String, Object?>>[wrongRow(wordId: 1)];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          // 全程答对且评级不是 HARD/EASY：从不产生错词记录。
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now),
        ];

      final outcome = merge(local, remote);

      expect(
        outcome.tables['wrong_word_states']!.where(
          (row) => row['word_id'] == 1,
        ),
        isEmpty,
      );
    });

    test('重算后熟练度写回词条行', () {
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')];
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now - 3 * day),
          logRow(id: 2, answerId: 'a-2', wordId: 1, reviewedAt: now),
        ];

      final outcome = merge(local, remote);
      final word = outcome.tables['words']!.single;
      expect(word['mastery_score'], greaterThan(0));
    });

    test('没有新作答时一本流水都不重放（卡片行对象不被替换）', () {
      final card = cardRow(wordId: 1, dueAt: 999);
      final local = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['review_cards'] = <Map<String, Object?>>[card];

      final outcome = merge(local, emptyTables());

      expect(outcome.counts.rebuiltWords, isZero);
      expect(identical(outcome.tables['review_cards']!.single, card), isTrue);
    });
  });

  group('设置', () {
    test('逐键取新', () {
      final local = emptyTables()
        ..['settings'] = <Map<String, Object?>>[
          settingRow(key: 'studyPlan', value: '旧', updatedAt: now - day),
          settingRow(key: 'aiRetryCount', value: '1'),
        ];
      final remote = emptyTables()
        ..['settings'] = <Map<String, Object?>>[
          settingRow(key: 'studyPlan', value: '新'),
          settingRow(key: 'aiRetryCount', value: '3', updatedAt: now - day),
          settingRow(key: 'questionTypeConfig', value: '{}'),
        ];

      final outcome = merge(local, remote);
      final byKey = <String, Map<String, Object?>>{
        for (final row in outcome.tables['settings']!)
          row['key']! as String: row,
      };

      expect(byKey['studyPlan']!['value_json'], '新');
      expect(byKey['aiRetryCount']!['value_json'], '1', reason: '本机更新');
      expect(byKey.containsKey('questionTypeConfig'), isTrue);
    });

    test('凭据与本机属性一律不搬', () {
      final local = emptyTables()
        ..['settings'] = <Map<String, Object?>>[
          settingRow(key: lanSyncSettingsKey, value: '{"port":9100}'),
          settingRow(key: webdavSettingsKey, value: '{"password":"local"}'),
          settingRow(key: llmConfigSettingsKey, value: '{"apiKey":"local"}'),
          settingRow(
            key: merriamWebsterDictionaryKeyName,
            value: '"local-key"',
          ),
        ];
      final remote = emptyTables()
        ..['settings'] = <Map<String, Object?>>[
          // 全部「更新」，用来证明排除规则生效。
          settingRow(
            key: lanSyncSettingsKey,
            value: '{"port":8765}',
            updatedAt: now + day,
          ),
          settingRow(
            key: webdavSettingsKey,
            value: '{"password":null}',
            updatedAt: now + day,
          ),
          settingRow(
            key: llmConfigSettingsKey,
            value: '{"apiKey":"remote"}',
            updatedAt: now + day,
          ),
          settingRow(
            key: merriamWebsterDictionaryKeyName,
            value: '"remote-key"',
            updatedAt: now + day,
          ),
        ];

      final outcome = merge(local, remote);
      final byKey = <String, Map<String, Object?>>{
        for (final row in outcome.tables['settings']!)
          row['key']! as String: row,
      };

      expect(byKey[lanSyncSettingsKey]!['value_json'], '{"port":9100}');
      expect(byKey[webdavSettingsKey]!['value_json'], '{"password":"local"}');
      expect(byKey[llmConfigSettingsKey]!['value_json'], '{"apiKey":"local"}');
      expect(
        byKey[merriamWebsterDictionaryKeyName]!['value_json'],
        '"local-key"',
      );
      expect(byKey, hasLength(4), reason: '被排除的键不会新增');
    });

    test('排除清单与凭据键名的唯一定义处一致', () {
      // 这两个 key 的常量定义在 feature 层，服务层用字面量引用；
      // 这条断言把两处钉在一起，改名时会红。
      expect(
        mergeExcludedSettingKeys,
        contains(merriamWebsterDictionaryKeyName),
      );
      expect(
        mergeExcludedSettingKeys,
        contains(merriamWebsterThesaurusKeyName),
      );
      expect(mergeExcludedSettingKeys, contains(llmConfigSettingsKey));
      expect(mergeExcludedSettingKeys, contains(lanSyncSettingsKey));
      expect(mergeExcludedSettingKeys, contains(webdavSettingsKey));
    });
  });

  group('幂等', () {
    test('同一份远端合并两次，第二次什么都不加', () {
      final local = emptyTables();
      final remote = emptyTables()
        ..['words'] = <Map<String, Object?>>[wordRow(id: 1, term: 'apple')]
        ..['word_contents'] = <Map<String, Object?>>[
          contentRow(wordId: 1, definitions: '苹果'),
        ]
        ..['study_sessions'] = <Map<String, Object?>>[
          sessionRow(id: 1, startedAt: now),
        ]
        ..['study_session_items'] = <Map<String, Object?>>[
          itemRow(id: 1, sessionId: 1, wordId: 1, position: 0),
        ]
        ..['review_logs'] = <Map<String, Object?>>[
          logRow(id: 1, answerId: 'a-1', wordId: 1, reviewedAt: now),
        ]
        ..['settings'] = <Map<String, Object?>>[
          settingRow(key: 'studyPlan', value: '{}'),
        ];

      final first = merge(local, remote);
      final second = merge(<String, List<Map<String, Object?>>>{
        for (final entry in first.tables.entries)
          entry.key: <Map<String, Object?>>[...entry.value],
      }, remote);

      expect(second.counts.addedWords, isZero);
      expect(second.counts.addedLogs, isZero);
      expect(second.counts.addedSessions, isZero);
      expect(second.counts.rebuiltWords, isZero, reason: '没有新流水就不重放');
      expect(second.tables['review_logs'], hasLength(1));
      expect(second.tables['words'], hasLength(1));
    });
  });
}
