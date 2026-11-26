import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/cloud_sync_progress.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_service.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_state_store.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';
import 'package:lexiloop/services/settings_service.dart';

class _FakeCloudSyncClient implements CloudSyncClient {
  new({required this.handshakeReply, required this.pullPages});

  final CloudSyncHandshakeReply handshakeReply;
  final List<CloudSyncPullPage> pullPages;
  final List<CloudSyncPullRequest> pullRequests = <CloudSyncPullRequest>[];
  final List<CloudSyncPushRequest> pushRequests = <CloudSyncPushRequest>[];

  @override
  Future<CloudSyncHandshakeReply> handshake(
    CloudSyncHandshakeRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async => handshakeReply;

  @override
  Future<CloudSyncPullPage> pullPage(
    CloudSyncPullRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    pullRequests.add(request);
    final idx = pullRequests.length - 1;
    return pullPages[idx.clamp(0, pullPages.length - 1)];
  }

  @override
  Future<CloudSyncPushReply> pushBatch(
    CloudSyncPushRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    pushRequests.add(request);
    final wordsCount = request.batch.tables['words']?.length ?? 0;
    return CloudSyncPushReply(
      summary: CloudSyncSideCounts(
        addedWords: wordsCount,
        wordCount: wordsCount + 1,
      ),
      datasetEpoch: handshakeReply.datasetEpoch,
      serverNow: handshakeReply.serverNow + 1000,
      wireBytes: 256,
    );
  }
}

Map<String, Object?> _wordRow({
  required int id,
  required String term,
  required int now,
}) => <String, Object?>{
  'id': id,
  'term': term,
  'normalized_term': term.toLowerCase(),
  'source_language': 'en',
  'target_language': 'zh-CN',
  'entry_type': 'WORD',
  'content_type': 'WORD',
  'initialization_status': 'READY',
  'mastery_level': 'NEW',
  'mastery_score': 0,
  'is_suspended': 0,
  'is_personal': 1,
  'created_at': now,
  'updated_at': now,
};

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late CloudSyncStateStore states;
  late LanSyncStateStore lanStates;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    states = CloudSyncStateStore(settings, clock: () => 1730000005000);
    lanStates = LanSyncStateStore(settings, clock: () => 1730000005000);
    await states.saveCredential(
      baseUrl: 'https://lexiloop.vercel.app',
      password: 'secret',
    );
  });

  tearDown(() => db.close());

  CloudSyncService buildService(_FakeCloudSyncClient fake) => CloudSyncService(
    (_) => fake,
    states,
    lanStates,
    CloudSyncLocalEngine(
      deltaExporter: IncrementalSyncExporter(db, clock: () => 1730000004000),
      incrementalMerger: IncrementalMergeService(
        db,
        settings,
        clock: () => 1730000005000,
      ),
      importer: BackupImporter(db),
    ),
    clock: () => 1730000005000,
  );

  test(
    'bidirectional sync paginates pull, pushes local word, and saves watermark',
    () async {
      // Seed 1 local word on Flutter
      await db.customStatement('''
INSERT INTO words (
  term, normalized_term, source_language, target_language,
  entry_type, content_type, initialization_status, mastery_level,
  mastery_score, is_suspended, is_personal, created_at, updated_at
) VALUES ('localword', 'localword', 'en', 'zh-CN', 'WORD', 'WORD',
  'READY', 'NEW', 0, 0, 1, 1730000000000, 1730000001000)
''');

      final fake = _FakeCloudSyncClient(
        handshakeReply: const CloudSyncHandshakeReply(
          deviceId: 'srv-01',
          datasetEpoch: 'srv-ep-1',
          serverNow: 1730000003000,
          wordCount: 2,
        ),
        pullPages: <CloudSyncPullPage>[
          CloudSyncPullPage(
            meta: const CloudSyncPullMeta(
              serverNow: 1730000003000,
              snapshotAt: 1730000003000,
              datasetEpoch: 'srv-ep-1',
              hasMore: true,
              nextCursor: <String, Object?>{'tableIndex': 0, 'lastId': 1},
            ),
            tables: <String, List<Map<String, Object?>>>{
              'words': <Map<String, Object?>>[
                _wordRow(id: 1, term: 'cloudone', now: 1730000002000),
              ],
            },
            wordRefs: const <Map<String, Object?>>[],
            wireBytes: 128,
            isIncremental: false,
          ),
          CloudSyncPullPage(
            meta: const CloudSyncPullMeta(
              serverNow: 1730000003000,
              snapshotAt: 1730000003000,
              datasetEpoch: 'srv-ep-1',
              hasMore: false,
            ),
            tables: <String, List<Map<String, Object?>>>{
              'words': <Map<String, Object?>>[
                _wordRow(id: 2, term: 'cloudtwo', now: 1730000002500),
              ],
            },
            wordRefs: const <Map<String, Object?>>[],
            wireBytes: 128,
            isIncremental: false,
          ),
        ],
      );

      final phases = <CloudSyncPhase>[];
      final result = await buildService(fake).sync(
        mode: CloudSyncMode.bidirectional,
        onProgress: (p) => phases.add(p.phase),
      );

      expect(fake.pullRequests, hasLength(2));
      expect(fake.pushRequests, hasLength(1));
      expect(fake.pushRequests.first.commitWatermark, isTrue);
      expect(fake.pushRequests.first.batch.tables['words'], hasLength(1));
      expect(result.local.addedWords, 2);
      expect(result.local.wordCount, 3);
      expect(result.peer.addedWords, 1);
      expect(
        phases,
        containsAll(<CloudSyncPhase>[
          CloudSyncPhase.connecting,
          CloudSyncPhase.pulling,
          CloudSyncPhase.pushing,
          CloudSyncPhase.merging,
          CloudSyncPhase.completed,
        ]),
      );

      final stored = await states.load();
      expect(stored.watermark?.serverDeviceId, 'srv-01');
      expect(stored.watermark?.serverCursorMs, 1730000003000);
      expect(stored.watermark?.localCursorMs, 1730000004000);
    },
  );

  test(
    'pullReplace replaces local DB while preserving cloudSync credentials',
    () async {
      await db.customStatement('''
INSERT INTO words (
  term, normalized_term, source_language, target_language,
  entry_type, content_type, initialization_status, mastery_level,
  mastery_score, is_suspended, is_personal, created_at, updated_at
) VALUES ('oldlocal', 'oldlocal', 'en', 'zh-CN', 'WORD', 'WORD',
  'READY', 'NEW', 0, 0, 1, 1730000000000, 1730000000000)
''');
      final oldEpoch = (await lanStates.ensureIdentity()).datasetEpoch;

      final fake = _FakeCloudSyncClient(
        handshakeReply: const CloudSyncHandshakeReply(
          deviceId: 'srv-01',
          datasetEpoch: 'srv-ep-2',
          serverNow: 1730000010000,
          wordCount: 1,
        ),
        pullPages: <CloudSyncPullPage>[
          CloudSyncPullPage(
            meta: const CloudSyncPullMeta(
              serverNow: 1730000010000,
              snapshotAt: 1730000010000,
              datasetEpoch: 'srv-ep-2',
              hasMore: false,
            ),
            tables: <String, List<Map<String, Object?>>>{
              'words': <Map<String, Object?>>[
                _wordRow(id: 1, term: 'freshcloud', now: 1730000009000),
              ],
            },
            wordRefs: const <Map<String, Object?>>[],
            wireBytes: 200,
            isIncremental: false,
          ),
        ],
      );

      final result = await buildService(fake)
          .sync(mode: CloudSyncMode.pullReplace);

      expect(result.local.wordCount, 1);
      final rows = await db.customSelect('SELECT term FROM words').get();
      expect(rows.map((r) => r.read<String>('term')).toList(), <String>[
        'freshcloud',
      ]);

      final stored = await states.load();
      expect(stored.credential?.baseUrl, 'https://lexiloop.vercel.app');
      expect(stored.credential?.password, 'secret');
      final newEpoch = (await lanStates.ensureIdentity()).datasetEpoch;
      expect(newEpoch, isNot(oldEpoch));
    },
  );
}
