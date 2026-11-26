/// 播放设置分组里「发音引擎优先级链」与「离线语音缓存管理」的 widget 测试。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/audio_cache_section.dart';
import 'package:lexiloop/features/settings/playback_section.dart';
import 'package:lexiloop/services/audio/audio_precache_service.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../services/audio/audio_fakes.dart';

const Key _youdaoToggleKey = Key('speechSourceToggle_youdao');
const Key _edgeToggleKey = Key('speechSourceToggle_edge');
const Key _systemToggleKey = Key('speechSourceToggle_system');
const Key _speechChainKey = Key('playbackSpeechChain');

/// 跟随 [appSettingsProvider] 重建的播放设置分组。
class _PlaybackWatch extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(appSettingsProvider)
      .when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Text('加载失败：$error'),
        data: (settings) => PlaybackSection(settings: settings),
      );
}

void main() {
  late AppDatabase db;
  late InMemorySpeechDiskCache diskCache;
  late FakeAudioDownloader downloader;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    diskCache = InMemorySpeechDiskCache();
    downloader = FakeAudioDownloader()..openGate();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          speechDiskCacheProvider.overrideWithValue(diskCache),
          audioDownloaderProvider.overrideWithValue(downloader),
          audioPrecacheServiceProvider.overrideWithValue(
            AudioPrecacheService(
              WordDao(db),
              downloader,
              diskCache,
              enableJitter: false,
            ),
          ),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: _PlaybackWatch()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// `settings` 表里某个键的原始值（未经类型化解析）。
  Future<Object?> storedValue(String key) async {
    final rows = await db.select(db.settings).get();
    for (final row in rows) {
      if (row.key == key) return jsonDecode(row.valueJson);
    }
    return null;
  }

  Switch switchOf(WidgetTester tester, Key key) =>
      tester.widget<Switch>(find.byKey(key));

  Future<void> waitForStoredChain(
    WidgetTester tester,
    bool Function(List<SpeechSourcePreference> chain) predicate,
  ) async {
    for (var i = 0; i < 20; i += 1) {
      await tester.pumpAndSettle();
      final reloaded = await SettingsService(SettingsDao(db)).load();
      if (predicate(reloaded.playback.speechChain)) return;
    }
  }

  group('发音引擎多选与优先级排序', () {
    testWidgets('展示三大引擎且已彻底移除 Next.js TTS', (tester) async {
      await pumpSection(tester);

      expect(find.text('有道词典发音'), findsWidgets);
      expect(find.text('微软 Edge 语音'), findsWidgets);
      expect(find.text('设备系统朗读'), findsOneWidget);
      expect(find.textContaining('Next.js'), findsNothing);
      expect(switchOf(tester, _youdaoToggleKey).value, isTrue);
      expect(switchOf(tester, _edgeToggleKey).value, isTrue);
      expect(switchOf(tester, _systemToggleKey).value, isTrue);
      expect(await storedValue('speechChain'), isNull);
    });

    testWidgets('单独开关某项引擎会持久化到 settings 表，全部关闭展示静音提示', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.byKey(_youdaoToggleKey));
      await waitForStoredChain(
        tester,
        (chain) =>
            !chain.firstWhere((e) => e.source == SpeechSource.youdao).enabled,
      );
      expect(switchOf(tester, _youdaoToggleKey).value, isFalse);
      expect(switchOf(tester, _edgeToggleKey).value, isTrue);

      await tester.tap(find.byKey(_edgeToggleKey));
      await waitForStoredChain(
        tester,
        (chain) =>
            !chain.firstWhere((e) => e.source == SpeechSource.edge).enabled,
      );
      await tester.tap(find.byKey(_systemToggleKey));
      await waitForStoredChain(
        tester,
        (chain) => chain.every((e) => !e.enabled),
      );

      expect(find.textContaining('静音模式'), findsOneWidget);
    });

    testWidgets('拖动排序会按新顺序持久化到 settings 表', (tester) async {
      await pumpSection(tester);

      final list = tester.widget<ReorderableListView>(
        find.byKey(_speechChainKey),
      );
      list.onReorderItem!(1, 0);
      await waitForStoredChain(
        tester,
        (chain) => chain.first.source == SpeechSource.edge,
      );

      final reloaded = await SettingsService(SettingsDao(db)).load();
      expect(
        reloaded.playback.speechChain.map((e) => e.source).toList(),
        <SpeechSource>[
          SpeechSource.edge,
          SpeechSource.youdao,
          SpeechSource.system,
        ],
      );
    });
  });

  group('离线语音缓存管理', () {
    testWidgets('展示分桶占用并支持单独清理有道与二次确认全清', (tester) async {
      await diskCache.write(
        SpeechCacheBucket.youdao,
        'u:apple',
        Uint8List.fromList(List<int>.filled(2048, 1)),
      );
      await diskCache.write(
        SpeechCacheBucket.edge,
        'US:sentence',
        Uint8List.fromList(List<int>.filled(4096, 2)),
      );
      await pumpSection(tester);

      expect(find.text('离线语音缓存'), findsOneWidget);
      expect(find.text('1 条 · 2.0 KB'), findsOneWidget);
      expect(find.text('1 条 · 4.0 KB'), findsOneWidget);

      // 单独清理有道，不影响 Edge
      await tester.tap(find.byKey(const Key('clearSpeechBucket_youdao')));
      await tester.pumpAndSettle();
      expect((await diskCache.stats()).youdaoFiles, 0);
      expect((await diskCache.stats()).edgeFiles, 1);

      // 清空全部（需经二次确认）
      await tester.tap(find.byKey(const Key('playbackClearAllAudioCache')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(clearAllAudioCacheConfirmKey));
      await tester.pumpAndSettle();
      expect((await diskCache.stats()).totalFiles, 0);
    });

    testWidgets('离线持久化开关可持久化到 settings 表', (tester) async {
      await pumpSection(tester);
      const toggleKey = Key('playbackOfflineAudioCache');
      expect(switchOf(tester, toggleKey).value, isTrue);

      await tester.tap(find.byKey(toggleKey));
      for (var i = 0; i < 20; i += 1) {
        await tester.pumpAndSettle();
        if (await storedValue('offlineAudioCacheEnabled') == false) break;
      }
      expect(await storedValue('offlineAudioCacheEnabled'), isFalse);
      expect(switchOf(tester, toggleKey).value, isFalse);
    });

    testWidgets('打开预缓存弹窗并执行离线批量缓存，完成后统计实时刷新', (tester) async {
      final stamp = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
      final id = await db
          .into(db.words)
          .insert(
            WordsCompanion.insert(
              term: 'resilient',
              normalizedTerm: 'resilient',
              sourceLanguage: 'en',
              targetLanguage: 'zh',
              entryType: EntryType.word,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(id),
              updatedAt: stamp,
            ),
          );

      await pumpSection(tester);
      await tester.tap(find.byKey(const Key('playbackOpenPrecache')));
      await tester.pumpAndSettle();

      expect(find.textContaining('共扫描 1 条语音'), findsOneWidget);
      await tester.tap(find.byKey(const Key('audioPrecacheStartButton')));
      await tester.pumpAndSettle();

      expect((await diskCache.stats()).youdaoFiles, 1);
      expect(find.textContaining('离线缓存完成'), findsOneWidget);
    });
  });

  group('AppSettings 往返', () {
    test('解析 → 序列化不丢 speechChain 顺序与开关状态', () {
      final raw = <String, Object?>{
        'speechChain': <Map<String, Object?>>[
          <String, Object?>{'source': 'system', 'enabled': true},
          <String, Object?>{'source': 'youdao', 'enabled': false},
          <String, Object?>{'source': 'edge', 'enabled': true},
        ],
      };
      final parsed = appSettingsFromRaw(raw);
      final roundTrip = appSettingsFromRaw(parsed.toStorage());

      expect(
        roundTrip.playback.speechChain
            .map((e) => (e.source, e.enabled))
            .toList(),
        parsed.playback.speechChain.map((e) => (e.source, e.enabled)).toList(),
      );
      expect(roundTrip.playback.enabledSpeechSources, <SpeechSource>[
        SpeechSource.system,
        SpeechSource.edge,
      ]);
    });
  });
}
