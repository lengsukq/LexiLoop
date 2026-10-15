/// 数据访问与领域服务的提供者。
///
/// 集中在一处，使「谁依赖谁」一眼可见；各 feature 只 import 本文件，
/// 不直接构造 DAO，避免同一服务被构造多份（例如 [SettingsService] 内部有
/// 缓存，构造两份就会出现「改了设置另一份看不到」）。
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/audio_downloader.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';
import 'package:lexiloop/services/audio/just_audio_engine.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/initialization/initialization_maintenance.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/initialization/initialization_worker.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
import 'package:lexiloop/services/initialization/supplemental_tasks.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/study_service.dart';
import 'package:lexiloop/services/tts_service.dart';

/// 词条查询。
final Provider<WordDao> wordDaoProvider = Provider<WordDao>(
  (ref) => WordDao(ref.watch(databaseProvider)),
);

/// 设置读写。
final Provider<SettingsDao> settingsDaoProvider = Provider<SettingsDao>(
  (ref) => SettingsDao(ref.watch(databaseProvider)),
);

/// 设置服务（含内存缓存，必须单例）。
final Provider<SettingsService> settingsServiceProvider =
    Provider<SettingsService>(
      (ref) => SettingsService(ref.watch(settingsDaoProvider)),
    );

/// 作答处理。
final Provider<ReviewService> reviewServiceProvider = Provider<ReviewService>(
  (ref) => ReviewService(
    ref.watch(databaseProvider),
    ref.watch(settingsServiceProvider),
  ),
);

/// 学习会话编排。
final Provider<StudyService> studyServiceProvider = Provider<StudyService>(
  (ref) => StudyService(
    ref.watch(databaseProvider),
    ref.watch(settingsServiceProvider),
  ),
);

/// 复习读写（供只读查询使用）。
final Provider<ReviewDao> reviewDaoProvider = Provider<ReviewDao>(
  (ref) => ReviewDao(ref.watch(databaseProvider)),
);

/// 学习会话读写（供只读查询使用）。
final Provider<StudyDao> studyDaoProvider = Provider<StudyDao>(
  (ref) => StudyDao(ref.watch(databaseProvider)),
);

/// 语音朗读。
///
/// 界面层通过这个 provider 取服务，测试里用 `overrideWithValue` 换成假引擎，
/// 避免在测试进程里初始化平台通道。
final Provider<TtsService> ttsServiceProvider = Provider<TtsService>(
  (ref) => TtsService(FlutterTtsEngine()),
);

/// 真人录音的下载器。
///
/// 界面层不要直接构造，测试里用 `overrideWithValue` 换成假下载器，
/// 避免在测试进程里真的发网络请求。
final Provider<AudioDownloadPort> audioDownloaderProvider =
    Provider<AudioDownloadPort>((ref) => DioAudioDownloader());

/// 真人录音的内存 LRU 缓存（必须单例）。
///
/// 缓存的价值全在「跨调用复用」上：构造多份等于每次播放都重新下载，
/// 那就等于没有缓存。
final Provider<AudioCache> audioCacheProvider = Provider<AudioCache>(
  (ref) => AudioCache(ref.watch(audioDownloaderProvider)),
);

/// 音频播放器。
///
/// [WordSpeaker] 通过它构造，但**不拥有**它的生命周期：谁构造谁释放。
/// 测试里覆盖这一个 provider 即可让整套发音链路不碰平台通道。
final Provider<AudioPlayerPort> audioPlayerPortProvider =
    Provider<AudioPlayerPort>((ref) {
      final engine = JustAudioEngine();
      ref.onDispose(() => unawaited(engine.dispose()));
      return engine;
    });

/// 词条发音：真人录音优先，系统朗读兜底。
///
/// 与 [ttsServiceProvider] 一样，测试应覆盖本 provider（或它的依赖
/// [audioCacheProvider] 与 [ttsServiceProvider]）而不是打到平台通道。
final Provider<WordSpeaker> wordSpeakerProvider = Provider<WordSpeaker>((ref) {
  final speaker = WordSpeaker(
    ref.watch(audioPlayerPortProvider),
    ref.watch(audioCacheProvider),
    ref.watch(ttsServiceProvider),
  );
  ref.onDispose(() => unawaited(speaker.stop()));
  return speaker;
});

/// 当前应用设置。
final FutureProvider<AppSettings> appSettingsProvider =
    FutureProvider<AppSettings>(
      (ref) => ref.watch(settingsServiceProvider).load(),
    );

/// 初始化任务队列的查询入口。
///
/// 放在这里而不是 `features/initialize`：[initializationJobRunnerProvider]
/// 也在本文件，而 data 层不允许反向依赖界面层——否则 worker 与查询会各拿一份实例。
final Provider<InitializationQueries> initializationQueriesProvider =
    Provider<InitializationQueries>(
      (ref) => InitializationQueries(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
      ),
    );

/// 共享的 HTTP 客户端（词典联网用）。
///
/// 单例而不是每次新建 `Dio`：`Dio` 内部有连接池，反复新建会丢掉复用，
/// 初始化队列一次 tick 可能连续调几十次。
final Provider<HttpFetcher> httpFetcherProvider = Provider<HttpFetcher>(
  (ref) => DioHttpFetcher(),
);

/// 初始化任务 worker。
///
/// **目前只在应用启动时由 [initializationMaintenanceProvider] 驱动，
/// 测试里直接构造。** 不要在界面层 `watch` 它跑任务，界面层只调
/// [InitializationMaintenance.pumpOnce]（带重入保护）。
final Provider<InitializationJobRunner> initializationJobRunnerProvider =
    Provider<InitializationJobRunner>(
      (ref) => InitializationWorker(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
        ref.watch(initializationQueriesProvider),
        DictionaryLookupService(ref.watch(httpFetcherProvider)),
        LlmSupplementalTaskRunner(
          ref.watch(databaseProvider),
          ref.watch(settingsServiceProvider),
          ref.watch(httpFetcherProvider),
        ),
      ),
    );

/// 初始化任务的后台维护（启动回收 + 定时 tick）。
///
/// 启动后 `dispose` 由 ProviderScope 接管，`main()` 里只需 `watch`（后点火，
/// 见 `lib/main.dart`）。启动那一步除了回收任务，还会顺带跑一次错词本衰减与
/// 导入批次过期——这两件事没有别的地方会做，不挂在这里就等于永远不做。
final Provider<InitializationMaintenance> initializationMaintenanceProvider =
    Provider<InitializationMaintenance>((ref) {
      final maintenance = InitializationMaintenance(
        ref.watch(initializationJobRunnerProvider),
      );
      ref.onDispose(maintenance.dispose);
      return maintenance;
    });
