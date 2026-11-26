/// 合并的收敛性：**两边各拉一次，两台设备的进度完全一致**。
///
/// 这是整个合并功能最重要的一条性质。单向覆盖做不到它——覆盖总是让一台设备的
/// 数据消失。合并是并集，因此：
///
///   1. B 从 A 拉一次 → B 拥有 A ∪ B；
///   2. A 从 B 拉一次 → A 也拥有 A ∪ B。
///
/// 「一致」在这里是**语义一致**：词条集合、作答集合、以及每个词的卡片状态
/// （FSRS 的三要素）相同。行 id 与 `updated_at` 不要求相同，它们本来就是
/// 本机的事实。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_lan_sync_client.dart';
import '../../support/free_udp_port.dart';

/// 合并时间的基准。
final int now = DateTime(2026, 6, 1, 9).millisecondsSinceEpoch;

void main() {
  late _Peer left;
  late _Peer right;

  setUp(() async {
    // 左：apple（两条流水）+ banana（一条）。
    left = await _Peer.spawn(
      deviceName: '左边的 Mac',
      words: <_SeedWord>[
        _SeedWord(
          term: 'apple',
          logs: <_SeedLog>[
            _SeedLog(reviewedAt: now - 10 * dayMs, rating: ReviewRating.good),
            _SeedLog(reviewedAt: now - 5 * dayMs, rating: ReviewRating.again),
          ],
        ),
        _SeedWord(
          term: 'banana',
          logs: <_SeedLog>[
            _SeedLog(reviewedAt: now - 3 * dayMs, rating: ReviewRating.easy),
          ],
        ),
      ],
    );
    // 右：apple（一条更晚的流水）+ cherry（一条）。
    // apple 在两边都有流水，合并后必须按时间顺序重放。
    right = await _Peer.spawn(
      deviceName: '右边的手机',
      words: <_SeedWord>[
        _SeedWord(
          term: 'apple',
          logs: <_SeedLog>[
            _SeedLog(reviewedAt: now - dayMs, rating: ReviewRating.hard),
          ],
        ),
        _SeedWord(
          term: 'cherry',
          logs: <_SeedLog>[
            _SeedLog(reviewedAt: now, rating: ReviewRating.good),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    await left.dispose();
    await right.dispose();
  });

  test('两边各合并一次之后，词条、作答与卡片完全一致', () async {
    // 1. 右边从左边的共享里拉一次。
    await left.serve();
    final first = await right.pullFrom(left, LanSyncPullMode.merge);
    // 左边有 apple 与 banana；右边已经有 apple，因此只新增 banana。
    expect(first.addedWords, 1, reason: 'apple 两边都有，只新增 banana');

    // 2. 左边再从右边（此时右边已是并集）拉一次。
    await right.serve();
    final second = await left.pullFrom(right, LanSyncPullMode.merge);
    // 左边的第二次：cherry 是新增的，apple 已在左，banana 已在左。
    expect(second.addedWords, 1, reason: '右边带来了 cherry');

    // **只比较词形，不比较 id**：id 是各机自己的自增主键，合并本来就会给
    // 远端行重新编号——那正是「两边的 id 不能直接拿来对」的原因。
    final leftWords = await left.words();
    final rightWords = await right.words();
    expect(leftWords.keys, rightWords.keys);
    expect(leftWords.keys.toSet(), <String>{'apple', 'banana', 'cherry'});

    final leftLogs = await left.logIds();
    final rightLogs = await right.logIds();
    expect(leftLogs, rightLogs);
    // 左 3 条（apple×2 + banana×1）+ 右 2 条（apple×1 + cherry×1）= 5 条。
    expect(leftLogs, hasLength(5), reason: '并集，没有重复');
  });

  test('交错复习过的词，卡片按合并后的流水重放且两边一致', () async {
    await left.serve();
    await right.pullFrom(left, LanSyncPullMode.merge);
    await right.serve();
    await left.pullFrom(right, LanSyncPullMode.merge);

    final leftCard = await left.cardOf('apple');
    final rightCard = await right.cardOf('apple');
    expect(leftCard, isNotNull);
    expect(rightCard, isNotNull);
    expect(leftCard, rightCard, reason: '同一条流水 + 同一个调度器 = 同一张卡');
    expect(leftCard!['reps'], 3, reason: 'apple 两边各 2 条与 1 条');
  });

  test('会话历史也收敛（统计页的会话数两台一致）', () async {
    // 给两边各造一场不同的会话，用一条流水挂上去。
    await left.attachSession(sessionStartedAt: now - 10 * dayMs);
    await right.attachSession(sessionStartedAt: now - dayMs);

    await left.serve();
    await right.pullFrom(left, LanSyncPullMode.merge);
    await right.serve();
    await left.pullFrom(right, LanSyncPullMode.merge);

    expect(await left.sessionCount(), 2);
    expect(await right.sessionCount(), 2);
  });

  test('收敛之后再多合一次不产生任何变化（稳定态）', () async {
    await left.serve();
    await right.pullFrom(left, LanSyncPullMode.merge);
    await right.serve();
    await left.pullFrom(right, LanSyncPullMode.merge);

    final before = (await left.words()).keys.toList()..sort();
    final logsBefore = await left.logIds();
    final cardsBefore = await left.cards();

    await left.serve();
    final again = await right.pullFrom(left, LanSyncPullMode.merge);
    await right.serve();
    final againLeft = await left.pullFrom(right, LanSyncPullMode.merge);

    expect(again.addedWords, isZero);
    expect(again.addedLogs, isZero);
    expect(againLeft.addedWords, isZero);
    expect(againLeft.addedLogs, isZero);
    expect((await left.words()).keys.toList()..sort(), before);
    expect(await left.logIds(), logsBefore);
    expect(await left.cards(), cardsBefore);
  });
}

/// 播种一条词条时用的流水。
class _SeedLog {
  const new({required this.reviewedAt, required this.rating});

  final int reviewedAt;
  final ReviewRating rating;
}

/// 播种一条词条。
class _SeedWord {
  const new({required this.term, required this.logs});

  final String term;
  final List<_SeedLog> logs;
}

/// 一台参与同步的设备：一个库、一份设置、一个可随时开启的共享服务端。
class _Peer {
  new({
    required this.db,
    required this.settings,
    required this.deviceName,
    required this.deviceId,
  });

  /// 以一份播种数据造一台设备。
  static Future<_Peer> spawn({
    required String deviceName,
    required List<_SeedWord> words,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final settings = SettingsService(SettingsDao(db));
    final peer = _Peer(
      db: db,
      settings: settings,
      deviceName: deviceName,
      deviceId: deviceName.hashCode & 0x7fffffff,
    );
    await BackupImporter(db).import(peer._backupJson(words));
    return peer;
  }

  final AppDatabase db;
  final SettingsService settings;
  final String deviceName;
  final int deviceId;

  LanSyncHost? _host;
  int _nextAnswerId = 0;

  /// 开启共享。
  Future<void> serve() async {
    await _host?.stop();
    _host = await createLanSyncHost(
      LanSyncHostOptions(
        deviceName: deviceName,
        port: 0,
        pairingCode: '246810',
        instanceId: 'peer-$deviceId',
        discoveryPort: await freeUdpPort(),
        backupSource: () async {
          final exported = await BackupExporter(db).exportToJson();
          return LanSyncBackup(
            bytes: exported.bytes,
            fileName: backupFileName(DateTime.now()),
            totalRows: exported.totalRows,
          );
        },
        onServed: (count) {},
        onCodeLockout: () {},
      ),
    );
  }

  /// 从 [other] 拉一次。
  Future<LanSyncPullResult> pullFrom(_Peer other, LanSyncPullMode mode) {
    final host = other._host;
    if (host == null) throw StateError('对端没有开启共享');
    final service = LanSyncPullService(
      LanSyncHttpClient.new,
      FakeLanSyncDiscovery(),
      BackupImporter(db),
      BackupMergeService(
        BackupExporter(db),
        BackupImporter(db),
        settings,
        clock: () => now,
      ),
      LanSyncStateStore(settings, clock: () => now),
    );
    return service.pull(
      host: DiscoveredLanHost(
        instanceId: 'peer-${other.deviceId}',
        deviceName: other.deviceName,
        address: '127.0.0.1',
        port: host.baseUri.port,
        protocolVersion: lanSyncProtocolVersion,
      ),
      pairingCode: '246810',
      mode: mode,
    );
  }

  /// 关掉共享并关闭数据库。
  Future<void> dispose() async {
    await _host?.stop();
    await db.close();
  }

  /// 词形 → id。
  Future<Map<String, int>> words() async {
    final rows = await db
        .customSelect('SELECT id, term FROM words ORDER BY term')
        .get();
    return <String, int>{
      for (final row in rows) row.read<String>('term'): row.read<int>('id'),
    };
  }

  /// 全部作答的幂等键（升序）。
  Future<List<String>> logIds() async {
    final rows = await db
        .customSelect(
          'SELECT client_answer_id FROM review_logs ORDER BY client_answer_id',
        )
        .get();
    return rows.map((row) => row.read<String>('client_answer_id')).toList();
  }

  /// 词形 → 卡片三要素。
  Future<Map<String, String>> cards() async {
    final rows = await db.customSelect('''
SELECT w.term AS term, c.due_at AS due_at, c.stability AS stability,
       c.difficulty AS difficulty, c.reps AS reps
FROM review_cards c JOIN words w ON w.id = c.word_id
ORDER BY w.term''').get();
    return <String, String>{
      for (final row in rows)
        row.read<String>('term'):
            '${row.read<int>('due_at')}/${row.read<double>('stability')}/'
            '${row.read<double>('difficulty')}/${row.read<int>('reps')}',
    };
  }

  /// 单个词的卡片三要素。
  Future<Map<String, Object?>?> cardOf(String term) async {
    final row = await db
        .customSelect(
          '''
SELECT c.due_at, c.stability, c.difficulty, c.reps
FROM review_cards c JOIN words w ON w.id = c.word_id
WHERE w.term = ?''',
          variables: <Variable<Object>>[Variable<String>(term)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  /// 会话数。
  Future<int> sessionCount() async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM study_sessions')
        .getSingle();
    return row.read<int>('c');
  }

  /// 给已有的第一场会话补一条流水（用来验证会话历史的收敛）。
  ///
  /// 直接写库而不是走复习流水线：这里要验的是**合并**，不是流水线。
  Future<void> attachSession({required int sessionStartedAt}) async {
    final sessionId = await db
        .into(db.studySessions)
        .insertReturning(
          StudySessionsCompanion.insert(
            sessionType: StudyMode.daily,
            startedAt: sessionStartedAt,
            createdAt: sessionStartedAt,
          ),
        );
    final wordRow = await db
        .customSelect('SELECT id FROM words ORDER BY id LIMIT 1')
        .getSingle();
    final wordId = wordRow.read<int>('id');
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId.id,
            position: 0,
            wordId: wordId,
            taskType: StudyTaskType.review,
            questionType: QuestionType.zhToEnSpelling,
            createdAt: sessionStartedAt,
          ),
        );
    _nextAnswerId += 1;
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: 'session-$deviceId-$_nextAnswerId',
            wordId: wordId,
            studySessionId: Value<int?>(sessionId.id),
            reviewedAt: sessionStartedAt,
            rating: ReviewRating.good,
            questionType: QuestionType.zhToEnSpelling,
            isCorrect: true,
            durationMs: const Value<int?>(3000),
            createdAt: sessionStartedAt,
          ),
        );
  }

  /// 一份播种用的备份 JSON。
  String _backupJson(List<_SeedWord> words) {
    final logs = <Map<String, Object?>>[];
    var wordId = 0;
    var logId = 0;
    for (final word in words) {
      wordId += 1;
      for (final log in word.logs) {
        logId += 1;
        logs.add(<String, Object?>{
          'id': logId,
          'client_answer_id': 'seed-$deviceId-$logId',
          'word_id': wordId,
          'reviewed_at': log.reviewedAt,
          'rating': log.rating.wire,
          'question_type': QuestionType.zhToEnSpelling.wire,
          'is_correct': 1,
          'duration_ms': 3000,
          'created_at': log.reviewedAt,
        });
      }
    }
    return jsonEncode(<String, Object?>{
      'format': backupFormat,
      'version': 3,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'words': <Map<String, Object?>>[
        for (final (index, word) in words.indexed)
          <String, Object?>{
            'id': index + 1,
            'term': word.term,
            'normalized_term': word.term.toLowerCase(),
            'source_language': 'en',
            'target_language': 'zh',
            'entry_type': EntryType.word.wire,
            'content_type': LexicalContentType.word.wire,
            'initialization_status': InitializationStatus.ready.wire,
            'mastery_level': MasteryLevel.newWord.wire,
            'mastery_score': 0,
            'is_suspended': 0,
            'created_at': now,
            'updated_at': now,
          },
      ],
      'review_logs': logs,
    });
  }
}
