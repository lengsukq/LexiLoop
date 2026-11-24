/// 词库离线语音批量预缓存服务单测。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/audio/audio_precache_service.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

import 'audio_fakes.dart';

class _FakeEdge implements DirectEdgeSpeechPort {
  final List<String> synthesized = <String>[];

  @override
  Future<Uint8List?> synthesize({
    required String text,
    required Accent accent,
  }) async {
    synthesized.add('${accent.wire}:$text');
    return Uint8List.fromList(<int>[9, 8, 7, 6]);
  }
}

void main() {
  late AppDatabase db;
  late FakeAudioDownloader downloader;
  late InMemorySpeechDiskCache disk;
  late _FakeEdge edge;
  late AudioPrecacheService service;
  final now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    downloader = FakeAudioDownloader()..openGate();
    disk = InMemorySpeechDiskCache();
    edge = _FakeEdge();
    service = AudioPrecacheService(
      WordDao(db),
      downloader,
      disk,
      edge: edge,
      enableJitter: false,
    );
  });

  tearDown(() => db.close());

  Future<int> insertWord(
    String term, {
    bool isPersonal = true,
    LexicalContentType contentType = LexicalContentType.word,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            contentType: Value<LexicalContentType>(contentType),
            isPersonal: Value<bool>(isPersonal),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(wordId: Value<int>(id), updatedAt: now),
        );
    return id;
  }

  Future<void> insertPackWithWords(String packId, List<int> wordIds) async {
    await db
        .into(db.wordPacks)
        .insert(
          WordPacksCompanion.insert(
            id: packId,
            slug: packId,
            name: 'CET-4 测试词书',
            category: const Value<String>('EXAM_CN'),
            description: const Value<String>('desc'),
            version: '1.0.0',
            contentMode: const Value<String>('ECDICT_BASE'),
            wordCount: Value<int>(wordIds.length),
            installedAt: now,
            updatedAt: now,
          ),
        );
    for (var i = 0; i < wordIds.length; i += 1) {
      await db
          .into(db.wordPackItems)
          .insert(
            WordPackItemsCompanion.insert(
              packId: packId,
              wordId: wordIds[i],
              rank: Value<int>(i + 1),
            ),
          );
    }
  }

  test('按全部 / 个人 / 指定词书三种范围精确筛选并落盘', () async {
    final personalId = await insertWord('apple');
    final packOnlyId = await insertWord('resilient', isPersonal: false);
    await insertPackWithWords('cet4', <int>[packOnlyId]);

    // 仅个人词库
    final personalResult = await service.run(
      const AudioPrecacheRequest(
        scope: AudioPrecacheScope.personalOnly,
        accentMode: AudioPrecacheAccentMode.defaultOnly,
        defaultAccent: Accent.us,
        maxCacheBytes: 0,
      ),
      onProgress: (_) {},
    );
    expect(personalResult.counts.total, 1);
    expect(personalResult.counts.downloaded, 1);
    expect(
      await disk.contains(
        SpeechCacheBucket.youdao,
        youdaoAudioUri('apple', Accent.us)!.toString(),
      ),
      isTrue,
    );
    expect(
      await disk.contains(
        SpeechCacheBucket.youdao,
        youdaoAudioUri('resilient', Accent.us)!.toString(),
      ),
      isFalse,
    );

    // 指定词书（美英双口音）
    final packResult = await service.run(
      AudioPrecacheRequest(
        scope: AudioPrecacheScope.wordPack(packId: 'cet4', packName: 'CET-4'),
        accentMode: AudioPrecacheAccentMode.bothUsAndUk,
        defaultAccent: Accent.us,
        maxCacheBytes: 0,
      ),
      onProgress: (_) {},
    );
    expect(packResult.counts.total, 2);
    expect(packResult.counts.downloaded, 2);
    expect(personalId, greaterThan(0));
    expect((await disk.stats()).youdaoFiles, 3);
  });

  test('断点续传：已落盘词条自动跳过且不重复联网', () async {
    await insertWord('apple');
    await insertWord('banana');
    await disk.write(
      SpeechCacheBucket.youdao,
      youdaoAudioUri('apple', Accent.us)!.toString(),
      Uint8List.fromList(<int>[1, 2, 3]),
    );

    final result = await service.run(
      const AudioPrecacheRequest(
        scope: AudioPrecacheScope.allWords,
        accentMode: AudioPrecacheAccentMode.defaultOnly,
        defaultAccent: Accent.us,
        maxCacheBytes: 0,
      ),
      onProgress: (_) {},
    );

    expect(result.status, AudioPrecacheStatus.completed);
    expect(result.counts.total, 2);
    expect(result.counts.skippedCached, 1);
    expect(result.counts.downloaded, 1);
    expect(downloader.downloaded, <Uri>[youdaoAudioUri('banana', Accent.us)!]);
  });

  test('整句默认跳过；勾选 Edge 补全时写入 edge 桶', () async {
    await insertWord(
      'This is a resilient team.',
      contentType: LexicalContentType.sentence,
    );

    final youdaoOnly = await service.estimate(
      scope: AudioPrecacheScope.allWords,
      accentMode: AudioPrecacheAccentMode.defaultOnly,
      defaultAccent: Accent.us,
    );
    expect(youdaoOnly.itemCount, 0);

    final withEdge = await service.run(
      const AudioPrecacheRequest(
        scope: AudioPrecacheScope.allWords,
        accentMode: AudioPrecacheAccentMode.defaultOnly,
        defaultAccent: Accent.us,
        maxCacheBytes: 0,
        includeEdgeFallback: true,
      ),
      onProgress: (_) {},
    );
    expect(withEdge.counts.downloaded, 1);
    expect(edge.synthesized, <String>['US:This is a resilient team.']);
    expect((await disk.stats()).edgeFiles, 1);
  });

  test('单条下载失败不中断整批，结束时按上限执行容量裁剪', () async {
    await insertWord('apple');
    await insertWord('broken');
    downloader.failing.add(youdaoAudioUri('broken', Accent.us)!.toString());

    final result = await service.run(
      const AudioPrecacheRequest(
        scope: AudioPrecacheScope.allWords,
        accentMode: AudioPrecacheAccentMode.defaultOnly,
        defaultAccent: Accent.us,
        maxCacheBytes: 1024,
      ),
      onProgress: (_) {},
    );

    expect(result.counts.downloaded, 1);
    expect(result.counts.failed, 1);
    expect(disk.enforcedLimits, <int>[1024]);
  });

  test('中途取消立即停止后续下载并标记为 cancelled', () async {
    await insertWord('worda');
    await insertWord('wordb');
    await insertWord('wordc');
    await insertWord('wordd');
    var cancelled = false;

    final result = await service.run(
      const AudioPrecacheRequest(
        scope: AudioPrecacheScope.allWords,
        accentMode: AudioPrecacheAccentMode.defaultOnly,
        defaultAccent: Accent.us,
        maxCacheBytes: 0,
      ),
      onProgress: (progress) {
        if (progress.counts.processed >= 1) cancelled = true;
      },
      isCancelled: () => cancelled,
    );

    expect(result.status, AudioPrecacheStatus.cancelled);
    expect(result.counts.downloaded, lessThanOrEqualTo(3));
  });
}
