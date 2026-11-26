import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/domain/sync/delta_batch_splitter.dart';

void main() {
  IncrementalSyncPayload buildSamplePayload({required int contentPadding}) {
    return IncrementalSyncPayload(
      isIncremental: false,
      serverNow: 1730000000000,
      datasetEpoch: 'epoch-1',
      wordRefs: const <Map<String, Object?>>[],
      tables: <String, List<Map<String, Object?>>>{
        'words': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'term': 'resilient',
            'normalized_term': 'resilient',
            'source_language': 'en',
            'target_language': 'zh-CN',
          },
          <String, Object?>{
            'id': 2,
            'term': 'ephemeral',
            'normalized_term': 'ephemeral',
            'source_language': 'en',
            'target_language': 'zh-CN',
          },
        ],
        'word_contents': <Map<String, Object?>>[
          <String, Object?>{
            'word_id': 1,
            'definitions_json': 'x' * contentPadding,
          },
          <String, Object?>{
            'word_id': 2,
            'definitions_json': 'y' * contentPadding,
          },
        ],
        'study_sessions': <Map<String, Object?>>[
          <String, Object?>{
            'id': 10,
            'started_at': 1730000000000,
            'session_type': 'DAILY',
            'source_type': null,
          },
        ],
        'study_session_items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 20,
            'study_session_id': 10,
            'position': 1.0,
            'word_id': 1,
          },
        ],
        'review_logs': <Map<String, Object?>>[
          <String, Object?>{
            'id': 30,
            'client_answer_id': 'ans-1',
            'word_id': 1,
            'study_session_id': 10,
            'study_session_item_id': 20,
            'reviewed_at': 1730000001000,
            'rating': 'GOOD',
            'is_correct': 1,
          },
        ],
        'settings': const <Map<String, Object?>>[],
        'word_packs': <Map<String, Object?>>[
          <String, Object?>{'id': 'ielts', 'slug': 'ielts', 'name': 'IELTS'},
        ],
        'word_pack_items': <Map<String, Object?>>[
          <String, Object?>{'pack_id': 'ielts', 'word_id': 2, 'rank': 1},
        ],
      },
    );
  }

  test('returns single batch on fast path when within maxBatchBytes', () {
    final payload = buildSamplePayload(contentPadding: 16);
    final batches = splitDeltaIntoPushBatches(payload, maxBatchBytes: 100000);
    expect(batches, hasLength(1));
    expect(batches.first.tables['words'], hasLength(2));
    expect(batches.first.tables['review_logs'], hasLength(1));
  });

  test('splits large payload in parent-first order with complete refs', () {
    final payload = buildSamplePayload(contentPadding: 800);
    final batches = splitDeltaIntoPushBatches(payload, maxBatchBytes: 1000);

    expect(batches.length, greaterThanOrEqualTo(5));
    expect(batches.first.tables.containsKey('words'), isTrue);

    final contentBatches = batches
        .where((b) => b.tables.containsKey('word_contents'))
        .toList();
    expect(contentBatches, hasLength(2));
    expect(contentBatches.first.wordRefs, hasLength(1));
    expect(contentBatches.first.wordRefs.first['normalized_term'], 'resilient');
    expect(contentBatches.last.wordRefs.first['normalized_term'], 'ephemeral');

    final logBatch = batches.firstWhere(
      (b) => b.tables.containsKey('review_logs'),
    );
    expect(logBatch.wordRefs.first['id'], 1);
    expect(logBatch.sessionRefs.first['id'], 10);
    expect(logBatch.itemRefs.first['id'], 20);

    final packItemBatch = batches.firstWhere(
      (b) => b.tables.containsKey('word_pack_items'),
    );
    expect(packItemBatch.wordRefs.first['normalized_term'], 'ephemeral');
  });
}
