/// 局域网同步 v2 全链路测试：真实 WebSocket + 真实 SQLite + GZip + 水位线增量 +
/// 一次配对双向收敛 + 进行中会话续传 + 3 设备纪元轮换 + 双端实时进度广播。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';
import 'package:lexiloop/services/merge/learning_replay.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../support/fake_lan_sync_client.dart';
import '../../support/free_udp_port.dart';

void main() {
  late _V2Peer mac;
  late _V2Peer phone;
  var virtualClock = DateTime(2026, 6, 1, 9).millisecondsSinceEpoch;

  setUp(() async {
    virtualClock = DateTime(2026, 6, 1, 9).millisecondsSinceEpoch;
    final seedTime = virtualClock - hourMs;
    mac = await _V2Peer.spawn(
      name: '书房 Mac',
      clock: () => virtualClock,
      seedAt: seedTime,
      words: <_WordSpec>[
        _WordSpec(
          term: 'apple',
          largeContent: true,
          logs: <_LogSpec>[
            _LogSpec(at: virtualClock - 10 * dayMs, rating: ReviewRating.good),
            _LogSpec(at: virtualClock - 5 * dayMs, rating: ReviewRating.again),
          ],
        ),
        _WordSpec(
          term: 'banana',
          largeContent: true,
          logs: <_LogSpec>[
            _LogSpec(at: virtualClock - 3 * dayMs, rating: ReviewRating.easy),
          ],
        ),
      ],
    );
    phone = await _V2Peer.spawn(
      name: '随身手机',
      clock: () => virtualClock,
      seedAt: seedTime,
      words: <_WordSpec>[
        _WordSpec(
          term: 'apple',
          logs: <_LogSpec>[
            _LogSpec(at: virtualClock - dayMs, rating: ReviewRating.hard),
          ],
        ),
        _WordSpec(
          term: 'cherry',
          largeContent: true,
          logs: <_LogSpec>[_LogSpec(at: seedTime, rating: ReviewRating.good)],
        ),
      ],
    );
  });

  tearDown(() async {
    await mac.dispose();
    await phone.dispose();
  });

  test('一次配对双向同步：双端直接收敛且都收到完整实时动画阶段', () async {
    final hostPhases = <LanSyncPhase>[];
    final clientPhases = <LanSyncPhase>[];

    await mac.startSharing(onProgress: hostPhases.add);
    final result = await phone.syncWith(
      mac,
      mode: LanSyncPullMode.bidirectional,
      onProgress: (p) => clientPhases.add(p.phase),
    );

    expect(result.mode, LanSyncPullMode.bidirectional);
    expect(result.addedWords, 1, reason: '手机新增 banana');
    expect(result.addedLogs, 3, reason: '手机新增 apple×2 + banana×1');
    expect(result.peerAddedWords, 1, reason: 'Mac 新增 cherry');
    expect(result.peerAddedLogs, 2, reason: 'Mac 新增 apple×1 + cherry×1');
    expect(result.transferredWireBytes, greaterThan(0));
    expect(result.transferredWireBytes, lessThan(result.uncompressedBytes));

    // 仅一次同步后两边词条、流水、FSRS 卡片与复习统计完全一致！
    expect(await mac.terms(), <String>['apple', 'banana', 'cherry']);
    expect(await phone.terms(), <String>['apple', 'banana', 'cherry']);
    expect(await mac.logIds(), await phone.logIds());
    expect(await mac.cardOf('apple'), await phone.cardOf('apple'));
    expect((await mac.cardOf('apple'))!['reps'], 3);
    expect(await mac.statsOf('apple'), await phone.statsOf('apple'));

    // 双端都经历了完整的实时动画阶段。
    expect(
      hostPhases,
      containsAllInOrder(<LanSyncPhase>[
        LanSyncPhase.connecting,
        LanSyncPhase.diffing,
        LanSyncPhase.transferring,
        LanSyncPhase.merging,
        LanSyncPhase.completed,
      ]),
    );
    expect(
      clientPhases,
      containsAllInOrder(<LanSyncPhase>[
        LanSyncPhase.connecting,
        LanSyncPhase.diffing,
        LanSyncPhase.transferring,
        LanSyncPhase.merging,
        LanSyncPhase.completed,
      ]),
    );
  });

  test('二次同步命中水位线增量：只传新日志与 word_refs，流量锐减且 FSRS 一致', () async {
    await mac.startSharing();
    final first = await phone.syncWith(
      mac,
      mode: LanSyncPullMode.bidirectional,
    );
    expect(first.isIncremental, isFalse, reason: '首次同步无水位线');

    // 时钟推进 1 分钟：Mac 给老词 apple 记一条新复习（不动 word_contents），手机加新词 date。
    virtualClock += minuteMs;
    await mac.addReviewLog('apple', reviewedAt: virtualClock);
    await phone.addWord('date', createdAt: virtualClock);

    final second = await phone.syncWith(
      mac,
      mode: LanSyncPullMode.bidirectional,
    );
    expect(second.isIncremental, isTrue, reason: '第二次命中双侧水位线');
    expect(second.addedLogs, 1);
    expect(second.peerAddedWords, 1);
    expect(
      second.uncompressedBytes,
      lessThan(first.uncompressedBytes ~/ 3),
      reason: '老词庞大的 word_contents 不应再被传输',
    );
    expect(await mac.terms(), <String>['apple', 'banana', 'cherry', 'date']);
    expect(await phone.terms(), <String>['apple', 'banana', 'cherry', 'date']);
    expect((await mac.cardOf('apple'))!['reps'], 4);
    expect(await mac.cardOf('apple'), await phone.cardOf('apple'));
  });

  test('进行中的学习会话后续完成后再增量同步，对端会推进为已完成', () async {
    await mac.startSharing();
    final sessionStart = virtualClock;
    final sessionId = await mac.createSession(
      startedAt: sessionStart,
      completedAt: null,
      completedCount: 1,
    );
    await phone.syncWith(mac, mode: LanSyncPullMode.bidirectional);
    expect(await phone.sessionCompletedAt(sessionStart), isNull);

    // 2 分钟后 Mac 完成该场会话。
    virtualClock += 2 * minuteMs;
    await mac.completeSession(sessionId, completedAt: virtualClock);
    await phone.syncWith(mac, mode: LanSyncPullMode.bidirectional);
    expect(await phone.sessionCompletedAt(sessionStart), virtualClock);
  });

  test('主机开启只读策略时拒绝双向同步，但允许单向合并', () async {
    await mac.states.setSharePolicy(LanSyncSharePolicy.readOnly);
    await mac.startSharing();

    await expectLater(
      phone.syncWith(mac, mode: LanSyncPullMode.bidirectional),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCode.lanSyncPeerRejected,
        ),
      ),
    );
    // 主机数据库完全不受影响（没有收到 cherry）。
    expect(await mac.terms(), <String>['apple', 'banana']);

    // 切到单向合并可以顺利拉取。
    final mergeResult = await phone.syncWith(mac, mode: LanSyncPullMode.merge);
    expect(mergeResult.addedWords, 1);
    expect(await phone.terms(), <String>['apple', 'banana', 'cherry']);
    expect(await mac.terms(), <String>['apple', 'banana']);
  });

  test('三设备拓扑下吸收第三台设备历史数据时自动轮换纪元，确保不漏历史词条', () async {
    final tablet = await _V2Peer.spawn(
      name: '客厅平板',
      clock: () => virtualClock,
      words: <_WordSpec>[
        _WordSpec(
          term: 'elderberry',
          // 刻意使用比水位线更早的历史时间戳！
          updatedAt: virtualClock - 20 * dayMs,
          logs: const <_LogSpec>[],
        ),
      ],
    );
    addTearDown(tablet.dispose);

    // 1. Mac 与 Phone 先双向同步建立水位线。
    await mac.startSharing();
    await phone.syncWith(mac, mode: LanSyncPullMode.bidirectional);

    // 2. Tablet 与 Mac 同步，把历史时间戳词条 elderberry 带给 Mac。
    virtualClock += minuteMs;
    await tablet.syncWith(mac, mode: LanSyncPullMode.bidirectional);
    expect(await mac.terms(), contains('elderberry'));

    // 3. Phone 再次同步 Mac：由于 Mac 检测到多设备合并轮换了 datasetEpoch，
    //    Phone 自动回退一次全量增量并完整拿到 elderberry！
    virtualClock += minuteMs;
    final third = await phone.syncWith(
      mac,
      mode: LanSyncPullMode.bidirectional,
    );
    expect(third.isIncremental, isFalse);
    expect(await phone.terms(), contains('elderberry'));
  });

  test('只评过 HARD（未曾答错）的词条在合并重放时正确写入错词表 updated_at', () async {
    final hardAt = virtualClock + minuteMs;
    await phone.addWord('fig', createdAt: hardAt);
    await phone.addReviewLog(
      'fig',
      reviewedAt: hardAt,
      rating: ReviewRating.hard,
    );
    await mac.startSharing();

    final result = await phone.syncWith(
      mac,
      mode: LanSyncPullMode.bidirectional,
    );
    expect(result.peerAddedWords, 2);
    expect(result.peerAddedLogs, 3);

    final wrongRows = await mac.db
        .customSelect(
          'SELECT w.term, ws.hard_count, ws.updated_at '
          'FROM wrong_word_states ws JOIN words w ON w.id = ws.word_id '
          "WHERE w.normalized_term = 'fig'",
        )
        .get();
    expect(wrongRows, hasLength(1));
    expect(wrongRows.single.read<int>('hard_count'), 1);
    expect(wrongRows.single.read<int>('updated_at'), hardAt);
  });
}

class _LogSpec {
  const new({required this.at, required this.rating});
  final int at;
  final ReviewRating rating;
}

class _WordSpec {
  const new({
    required this.term,
    required this.logs,
    this.largeContent = false,
    this.updatedAt,
  });
  final String term;
  final List<_LogSpec> logs;
  final bool largeContent;
  final int? updatedAt;
}

class _V2Peer {
  new({
    required this.db,
    required this.settings,
    required this.states,
    required this.shareService,
    required this.pullService,
    required this.name,
  });

  static Future<_V2Peer> spawn({
    required String name,
    required int Function() clock,
    required List<_WordSpec> words,
    int? seedAt,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final settings = SettingsService(SettingsDao(db));
    final states = LanSyncStateStore(settings, clock: clock);
    await states.setDeviceName(name);
    await states.setPort(0);
    await states.ensureIdentity();
    final exporter = BackupExporter(db);
    final importer = BackupImporter(db);
    final deltaExporter = IncrementalSyncExporter(db, clock: clock);
    final incMerger = IncrementalMergeService(db, settings, clock: clock);
    final discoveryPort = await freeUdpPort();
    final share = LanSyncShareService(
      exporter,
      (options) => createLanSyncHost(
        LanSyncHostOptions(
          deviceName: options.deviceName,
          port: 0,
          pairingCode: options.pairingCode,
          instanceId: options.instanceId,
          discoveryPort: discoveryPort,
          deviceId: options.deviceId,
          deviceKind: options.deviceKind,
          datasetEpoch: options.datasetEpoch,
          allowsBidirectional: options.allowsBidirectional,
          backupSource: options.backupSource,
          sessionDelegate: options.sessionDelegate,
          onCodeLockout: options.onCodeLockout,
          onServed: options.onServed,
        ),
      ),
      states,
      deltaExporter: deltaExporter,
      incrementalMerger: incMerger,
      codeGenerator: () => '246810',
      clock: clock,
    );
    final pull = LanSyncPullService(
      LanSyncHttpClient.new,
      FakeLanSyncDiscovery(),
      importer,
      BackupMergeService(exporter, importer, settings, clock: clock),
      states,
      sessionRunner: runLanSyncClientSession,
      deltaExporter: deltaExporter,
      incrementalMerger: incMerger,
      clock: clock,
    );

    final peer = _V2Peer(
      db: db,
      settings: settings,
      states: states,
      shareService: share,
      pullService: pull,
      name: name,
    );
    await peer._seed(words, seedAt ?? clock());
    return peer;
  }

  final AppDatabase db;
  final SettingsService settings;
  final LanSyncStateStore states;
  final LanSyncShareService shareService;
  final LanSyncPullService pullService;
  final String name;
  int _seq = 0;

  Future<void> startSharing({void Function(LanSyncPhase)? onProgress}) async {
    await shareService.start(
      onServed: () {},
      onLockedOut: () {},
      onProgress: () {
        final phase = shareService.session?.liveProgress?.phase;
        if (phase != null) onProgress?.call(phase);
      },
    );
  }

  Future<LanSyncPullResult> syncWith(
    _V2Peer hostPeer, {
    required LanSyncPullMode mode,
    void Function(LanSyncTransferProgress)? onProgress,
  }) {
    final session = hostPeer.shareService.session!;
    final target = DiscoveredLanHost(
      instanceId: session.instanceId,
      deviceName: session.deviceName,
      address: '127.0.0.1',
      port: session.baseUri.port,
      protocolVersion: lanSyncProtocolVersion,
      deviceKind: session.deviceKind,
      allowsBidirectional:
          session.sharePolicy == LanSyncSharePolicy.bidirectional,
    );
    return pullService.pull(
      host: target,
      pairingCode: session.pairingCode,
      mode: mode,
      onProgress: onProgress,
    );
  }

  Future<void> addWord(String term, {required int createdAt}) async {
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
  }

  Future<void> addReviewLog(
    String term, {
    required int reviewedAt,
    ReviewRating rating = ReviewRating.good,
  }) async {
    final row = await db
        .customSelect(
          'SELECT id FROM words WHERE normalized_term = ?',
          variables: <Variable<Object>>[Variable<String>(term.toLowerCase())],
        )
        .getSingle();
    final wordId = row.read<int>('id');
    _seq += 1;
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: '$name-live-$_seq',
            wordId: wordId,
            reviewedAt: reviewedAt,
            rating: rating,
            questionType: QuestionType.enToZhChoice,
            isCorrect: rating != ReviewRating.again,
            durationMs: const Value<int?>(2500),
            createdAt: reviewedAt,
          ),
        );
    // 模拟真实复习流水线：本机作答后同步更新本机 review_cards。
    final logs = await db
        .customSelect(
          'SELECT * FROM review_logs WHERE word_id = ? '
          'ORDER BY reviewed_at ASC, client_answer_id ASC',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    final replayed = replayWordHistory(
      logs: logs.map((r) => replayLogFromRow(r.data)).toList(growable: false),
      scheduler: FsrsScheduler(),
      now: reviewedAt,
    );
    await db.customStatement(
      'INSERT INTO review_cards '
      '(word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, '
      'reps, lapses, fsrs_state, learning_steps, last_review_at, '
      'created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(word_id) DO UPDATE SET '
      'due_at = excluded.due_at, stability = excluded.stability, '
      'difficulty = excluded.difficulty, elapsed_days = excluded.elapsed_days, '
      'scheduled_days = excluded.scheduled_days, reps = excluded.reps, '
      'lapses = excluded.lapses, fsrs_state = excluded.fsrs_state, '
      'learning_steps = excluded.learning_steps, '
      'last_review_at = excluded.last_review_at, '
      'updated_at = excluded.updated_at',
      <Object?>[
        wordId,
        replayed.card.dueAt,
        replayed.card.stability,
        replayed.card.difficulty,
        replayed.card.elapsedDays,
        replayed.card.scheduledDays,
        replayed.card.reps,
        replayed.card.lapses,
        replayed.card.fsrsState,
        replayed.card.learningSteps,
        replayed.card.lastReviewAt,
        replayed.card.dueAt,
        reviewedAt,
      ],
    );
  }

  Future<int> createSession({
    required int startedAt,
    required int? completedAt,
    required int completedCount,
  }) async {
    final session = await db
        .into(db.studySessions)
        .insertReturning(
          StudySessionsCompanion.insert(
            sessionType: StudyMode.daily,
            startedAt: startedAt,
            completedAt: Value<int?>(completedAt),
            plannedCount: const Value<int>(2),
            completedCount: Value<int>(completedCount),
            createdAt: startedAt,
          ),
        );
    final word = await db
        .customSelect('SELECT id FROM words ORDER BY id LIMIT 1')
        .getSingle();
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: session.id,
            position: 0,
            wordId: word.read<int>('id'),
            taskType: StudyTaskType.review,
            questionType: QuestionType.enToZhChoice,
            status: const Value<StudyItemStatus>(StudyItemStatus.answered),
            answeredAt: Value<int?>(startedAt),
            createdAt: startedAt,
          ),
        );
    return session.id;
  }

  Future<void> completeSession(int id, {required int completedAt}) =>
      db.customStatement(
        'UPDATE study_sessions SET completed_at = ?, completed_count = 2 '
        'WHERE id = ?',
        <Object?>[completedAt, id],
      );

  Future<int?> sessionCompletedAt(int startedAt) async {
    final row = await db
        .customSelect(
          'SELECT completed_at FROM study_sessions WHERE started_at = ?',
          variables: <Variable<Object>>[Variable<int>(startedAt)],
        )
        .getSingleOrNull();
    return row?.readNullable<int>('completed_at');
  }

  Future<List<String>> terms() async {
    final rows = await db
        .customSelect('SELECT term FROM words ORDER BY term')
        .get();
    return rows.map((r) => r.read<String>('term')).toList();
  }

  Future<List<String>> logIds() async {
    final rows = await db
        .customSelect(
          'SELECT client_answer_id FROM review_logs ORDER BY client_answer_id',
        )
        .get();
    return rows.map((r) => r.read<String>('client_answer_id')).toList();
  }

  Future<Map<String, Object?>?> cardOf(String term) async {
    final row = await db
        .customSelect(
          'SELECT c.due_at, c.stability, c.difficulty, c.reps '
          'FROM review_cards c JOIN words w ON w.id = c.word_id '
          'WHERE w.term = ?',
          variables: <Variable<Object>>[Variable<String>(term)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  Future<Map<String, Object?>?> statsOf(String term) async {
    final row = await db
        .customSelect(
          'SELECT s.total_reviews, s.correct_reviews, s.last_reviewed_at '
          'FROM word_review_stats s JOIN words w ON w.id = s.word_id '
          'WHERE w.term = ?',
          variables: <Variable<Object>>[Variable<String>(term)],
        )
        .getSingleOrNull();
    return row?.data;
  }

  Future<void> dispose() async {
    await shareService.stop();
    await db.close();
  }

  Future<void> _seed(List<_WordSpec> words, int now) async {
    for (final spec in words) {
      final ts = spec.updatedAt ?? now;
      final inserted = await db
          .into(db.words)
          .insertReturning(
            WordsCompanion.insert(
              term: spec.term,
              normalizedTerm: spec.term.toLowerCase(),
              sourceLanguage: 'en',
              targetLanguage: 'zh',
              entryType: EntryType.word,
              initializationStatus: const Value<InitializationStatus>(
                InitializationStatus.ready,
              ),
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      if (spec.largeContent) {
        final defs = jsonEncode(
          List<Map<String, String>>.generate(
            40,
            (i) => <String, String>{
              'pos': 'n.',
              'meaning': 'detailed dictionary entry #$i for ${spec.term} ' * 3,
            },
          ),
        );
        await db
            .into(db.wordContents)
            .insert(
              WordContentsCompanion.insert(
                wordId: Value<int>(inserted.id),
                definitionsJson: Value<String>(defs),
                updatedAt: ts,
              ),
            );
      }
      for (final log in spec.logs) {
        _seq += 1;
        await db
            .into(db.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                clientAnswerId: '$name-seed-$_seq',
                wordId: inserted.id,
                reviewedAt: log.at,
                rating: log.rating,
                questionType: QuestionType.enToZhChoice,
                isCorrect: log.rating != ReviewRating.again,
                durationMs: const Value<int?>(3000),
                createdAt: log.at,
              ),
            );
      }
    }
  }
}
