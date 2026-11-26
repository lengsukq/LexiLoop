/// 词库离线语音批量预缓存服务。
///
/// 按用户选定的范围（全部词条 / 个人词库 / 指定已安装词书）与口音批量拉取
/// 有道 MP3（并可选用 Edge 补全整句/缺失词）写入统一磁盘缓存，天然支持
/// 断点续传（已落盘词条自动跳过）、取消任务与友好节流。
library;

import 'dart:async';
import 'dart:math' show Random, min;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/audio/audio_downloader.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

final RegExp _youdaoPrecacheTermPattern = RegExp(r"^[a-zA-Z][a-zA-Z '\-]*$");
final RegExp _precacheWhitespace = RegExp(r'\s+');

/// 批量预缓存范围类型。
enum AudioPrecacheScopeKind {
  /// 全部词条（个人词库 + 全部已安装词书）。
  allWords,

  /// 仅个人词库词条。
  personalOnly,

  /// 指定某本已安装词书。
  wordPack,
}

/// 批量预缓存范围描述。
class AudioPrecacheScope {
  /// 构造范围对象。
  const new({required this.kind, this.packId, this.packName});

  /// 指定已安装词书。
  factory wordPack({required String packId, required String packName}) =>
      AudioPrecacheScope(
        kind: AudioPrecacheScopeKind.wordPack,
        packId: packId,
        packName: packName,
      );

  /// 全部词条。
  static const AudioPrecacheScope allWords = AudioPrecacheScope(
    kind: AudioPrecacheScopeKind.allWords,
  );

  /// 仅个人词库。
  static const AudioPrecacheScope personalOnly = AudioPrecacheScope(
    kind: AudioPrecacheScopeKind.personalOnly,
  );

  /// 范围类型。
  final AudioPrecacheScopeKind kind;

  /// 当 [kind] 为 [AudioPrecacheScopeKind.wordPack] 时的词书 ID。
  final String? packId;

  /// 词书展示名。
  final String? packName;

  /// 展示给用户的范围名称。
  String get label => switch (kind) {
    AudioPrecacheScopeKind.allWords => '全部词条',
    AudioPrecacheScopeKind.personalOnly => '仅个人词库',
    AudioPrecacheScopeKind.wordPack => packName ?? '指定词书',
  };
}

/// 预缓存口音模式。
enum AudioPrecacheAccentMode {
  /// 仅缓存当前默认口音。
  defaultOnly('仅当前默认口音'),

  /// 同时缓存美音与英音。
  bothUsAndUk('美音 + 英音双口音');

  new(this.label);

  /// 展示文案。
  final String label;

  /// 返回实际要缓存的口音列表。
  List<Accent> resolveAccents(Accent defaultAccent) => switch (this) {
    AudioPrecacheAccentMode.defaultOnly => <Accent>[defaultAccent],
    AudioPrecacheAccentMode.bothUsAndUk => const <Accent>[Accent.us, Accent.uk],
  };
}

/// 批量预缓存任务状态。
enum AudioPrecacheStatus {
  /// 空闲。
  idle,

  /// 正在扫描目标词条。
  scanning,

  /// 正在并发下载并写入磁盘缓存。
  running,

  /// 正在响应取消请求。
  cancelling,

  /// 全部处理完成。
  completed,

  /// 用户中途取消（已完成项已安全落盘，下次自动续传）。
  cancelled,
}

/// 批量预缓存计数快照。
class AudioPrecacheCounts {
  /// 以各计数构造。
  const new({
    required this.total,
    required this.skippedCached,
    required this.downloaded,
    required this.failed,
    required this.addedBytes,
  });

  /// 全零初始态。
  static const AudioPrecacheCounts zero = AudioPrecacheCounts(
    total: 0,
    skippedCached: 0,
    downloaded: 0,
    failed: 0,
    addedBytes: 0,
  );

  /// 本次扫描得到的目标语音总数（含不同口音）。
  final int total;

  /// 已在本地磁盘命中而跳过的条数。
  final int skippedCached;

  /// 本次新下载并落盘成功的条数。
  final int downloaded;

  /// 本次下载失败的条数。
  final int failed;

  /// 本次新写入磁盘的总字节数。
  final int addedBytes;

  /// 已处理总数。
  int get processed => skippedCached + downloaded + failed;

  /// 完成进度（0.0–1.0）。
  double get fraction => total == 0 ? 0 : (processed / total).clamp(0, 1);
}

/// 批量预缓存实时进度快照。
class AudioPrecacheProgress {
  /// 以状态、计数、当前词条与范围名构造。
  const new({
    required this.status,
    required this.counts,
    this.currentTerm = '',
    this.scopeLabel = '',
  });

  /// 空闲态。
  static const AudioPrecacheProgress idle = AudioPrecacheProgress(
    status: AudioPrecacheStatus.idle,
    counts: AudioPrecacheCounts.zero,
  );

  /// 当前阶段。
  final AudioPrecacheStatus status;

  /// 统计计数。
  final AudioPrecacheCounts counts;

  /// 最近处理到的词条。
  final String currentTerm;

  /// 任务范围展示名。
  final String scopeLabel;

  /// 是否正在运行中。
  bool get isActive =>
      status == AudioPrecacheStatus.scanning ||
      status == AudioPrecacheStatus.running ||
      status == AudioPrecacheStatus.cancelling;
}

/// 一次预缓存任务的入参。
class AudioPrecacheRequest {
  /// 以范围、口音模式、默认口音、是否启用 Edge 补全与上限构造。
  const new({
    required this.scope,
    required this.accentMode,
    required this.defaultAccent,
    required this.maxCacheBytes,
    this.includeEdgeFallback = false,
  });

  /// 目标范围。
  final AudioPrecacheScope scope;

  /// 口音模式。
  final AudioPrecacheAccentMode accentMode;

  /// 设置里的默认口音。
  final Accent defaultAccent;

  /// 容量上限（字节）；`0` 表示不限制。
  final int maxCacheBytes;

  /// 是否用 Edge 顺带缓存整句或有道下载失败的词条。
  final bool includeEdgeFallback;
}

/// 预缓存估算结果。
class AudioPrecacheEstimate {
  /// 以候选语音条数与预估总字节数构造。
  const new({required this.itemCount, required this.estimatedBytes});

  /// 目标语音条数。
  final int itemCount;

  /// 按有道均摊大小预估的新增上限字节数。
  final int estimatedBytes;
}

/// 批量预缓存执行服务。
class AudioPrecacheService {
  /// 以词条 DAO、下载器、磁盘缓存与可选 Edge 合成器构造。
  new(
    this._wordDao,
    this._downloader,
    this._diskCache, {
    this.edge,
    this.enableJitter = true,
  });

  final WordDao _wordDao;
  final AudioDownloadPort _downloader;
  final SpeechDiskCachePort _diskCache;

  /// 可选 Edge 合成器，供用户开启整句/缺失词补全时使用。
  final DirectEdgeSpeechPort? edge;

  /// 是否在两次请求间插入友好抖动延迟（单测可关闭）。
  final bool enableJitter;
  final Random _random = Random();

  /// 估算目标范围内可预缓存的语音条数与大致体积。
  Future<AudioPrecacheEstimate> estimate({
    required AudioPrecacheScope scope,
    required AudioPrecacheAccentMode accentMode,
    required Accent defaultAccent,
    bool includeEdgeFallback = false,
  }) async {
    final jobs = await _buildJobs(
      scope: scope,
      accents: accentMode.resolveAccents(defaultAccent),
      includeEdgeFallback: includeEdgeFallback,
    );
    return AudioPrecacheEstimate(
      itemCount: jobs.length,
      estimatedBytes: jobs.length * audioEstimatedBytesPerWord,
    );
  }

  /// 执行批量预缓存；支持通过 [isCancelled] 随时安全中断。
  Future<AudioPrecacheProgress> run(
    AudioPrecacheRequest request, {
    required void Function(AudioPrecacheProgress progress) onProgress,
    bool Function()? isCancelled,
  }) async {
    final cancelled = isCancelled ?? () => false;
    onProgress(
      AudioPrecacheProgress(
        status: AudioPrecacheStatus.scanning,
        counts: AudioPrecacheCounts.zero,
        scopeLabel: request.scope.label,
      ),
    );
    final jobs = await _buildJobs(
      scope: request.scope,
      accents: request.accentMode.resolveAccents(request.defaultAccent),
      includeEdgeFallback: request.includeEdgeFallback,
    );
    final tracker = _PrecacheTracker(jobs.length, request.scope.label);
    onProgress(tracker.snapshot(AudioPrecacheStatus.running));
    if (jobs.isNotEmpty) {
      await _drainJobs(jobs, request, tracker, onProgress, cancelled);
    }
    if (request.maxCacheBytes > 0) {
      await _diskCache.enforceLimit(request.maxCacheBytes);
    }
    final finalStatus = cancelled()
        ? AudioPrecacheStatus.cancelled
        : AudioPrecacheStatus.completed;
    final done = tracker.snapshot(finalStatus);
    onProgress(done);
    return done;
  }

  Future<void> _drainJobs(
    List<_PrecacheJob> jobs,
    AudioPrecacheRequest request,
    _PrecacheTracker tracker,
    void Function(AudioPrecacheProgress progress) onProgress,
    bool Function() isCancelled,
  ) async {
    var cursor = 0;
    final workers = min(audioPrecacheConcurrency, jobs.length);
    await Future.wait(<Future<void>>[
      for (var worker = 0; worker < workers; worker += 1)
        () async {
          while (!isCancelled()) {
            final index = cursor++;
            if (index >= jobs.length) return;
            await _processOne(jobs[index], request, tracker);
            onProgress(
              tracker.snapshot(
                isCancelled()
                    ? AudioPrecacheStatus.cancelling
                    : AudioPrecacheStatus.running,
              ),
            );
          }
        }(),
    ]);
  }

  Future<void> _processOne(
    _PrecacheJob job,
    AudioPrecacheRequest request,
    _PrecacheTracker tracker,
  ) async {
    tracker.currentTerm = job.term;
    if (await _alreadyCached(job, includeEdge: request.includeEdgeFallback)) {
      tracker.skippedCached += 1;
      return;
    }
    final ok = await _fetchAndStore(job, request, tracker);
    if (!ok) tracker.failed += 1;
    if (enableJitter) await _jitterDelay();
  }

  Future<bool> _alreadyCached(
    _PrecacheJob job, {
    required bool includeEdge,
  }) async {
    for (final url in job.youdaoUrls) {
      if (await _diskCache.contains(SpeechCacheBucket.youdao, url.toString())) {
        return true;
      }
    }
    if (includeEdge) {
      final edgeKey = edgeSpeechCacheKey(job.term, job.accent);
      return await _diskCache.contains(SpeechCacheBucket.edge, edgeKey);
    }
    return false;
  }

  Future<bool> _fetchAndStore(
    _PrecacheJob job,
    AudioPrecacheRequest request,
    _PrecacheTracker tracker,
  ) async {
    for (final url in job.youdaoUrls) {
      try {
        final bytes = await _downloader.download(url);
        if (bytes.isEmpty) continue;
        await _diskCache.write(SpeechCacheBucket.youdao, url.toString(), bytes);
        tracker
          ..downloaded += 1
          ..addedBytes += bytes.length;
        return true;
      } on Object {
        // 单个地址失败继续尝试下一个候选或可选 Edge 补全。
      }
    }
    final edgeService = edge;
    if (!request.includeEdgeFallback || edgeService == null) return false;
    final audio = await edgeService.synthesize(
      text: job.term,
      accent: job.accent,
    );
    if (audio == null || audio.isEmpty) return false;
    final key = edgeSpeechCacheKey(job.term, job.accent);
    await _diskCache.write(SpeechCacheBucket.edge, key, audio);
    tracker
      ..downloaded += 1
      ..addedBytes += audio.length;
    return true;
  }

  Future<List<_PrecacheJob>> _buildJobs({
    required AudioPrecacheScope scope,
    required List<Accent> accents,
    required bool includeEdgeFallback,
  }) async {
    final targets = await _wordDao.listAudioPrecacheTargets(
      personalOnly: scope.kind == AudioPrecacheScopeKind.personalOnly,
      packId: scope.kind == AudioPrecacheScopeKind.wordPack
          ? scope.packId
          : null,
    );
    final seen = <String>{};
    final jobs = <_PrecacheJob>[];
    for (final target in targets) {
      final trimmed = target.term.trim();
      if (trimmed.isEmpty) continue;
      for (final accent in accents) {
        final key = '${accent.wire}:${trimmed.toLowerCase()}';
        if (!seen.add(key)) continue;
        final urls = _youdaoUrlsFor(target, accent);
        if (urls.isEmpty && !includeEdgeFallback) continue;
        jobs.add(_PrecacheJob(trimmed, accent, urls));
      }
    }
    return jobs;
  }

  List<Uri> _youdaoUrlsFor(AudioPrecacheWordTarget target, Accent accent) {
    final seen = <String>{};
    final urls = <Uri>[];
    void add(Uri? uri) {
      if (uri != null && seen.add(uri.toString())) urls.add(uri);
    }

    add(
      resolveHumanAudioUrl(
        term: target.term,
        accent: accent,
        pronunciations: target.pronunciations,
      ),
    );
    if (target.contentType != LexicalContentType.sentence) {
      final trimmed = target.term.trim();
      final words = trimmed.split(_precacheWhitespace).length;
      if (_youdaoPrecacheTermPattern.hasMatch(trimmed) &&
          words <= youdaoDirectMaxWords) {
        add(youdaoAudioUri(trimmed, accent));
      }
    }
    return urls;
  }

  Future<void> _jitterDelay() {
    const span = audioPrecacheJitterMaxMs - audioPrecacheJitterMinMs;
    final ms = audioPrecacheJitterMinMs + _random.nextInt(span + 1);
    return Future<void>.delayed(Duration(milliseconds: ms));
  }
}

class _PrecacheJob {
  const new(this.term, this.accent, this.youdaoUrls);

  final String term;
  final Accent accent;
  final List<Uri> youdaoUrls;
}

class _PrecacheTracker {
  new(this.total, this.scopeLabel);

  final int total;
  final String scopeLabel;
  int skippedCached = 0;
  int downloaded = 0;
  int failed = 0;
  int addedBytes = 0;
  String currentTerm = '';

  AudioPrecacheProgress snapshot(AudioPrecacheStatus status) =>
      AudioPrecacheProgress(
        status: status,
        counts: AudioPrecacheCounts(
          total: total,
          skippedCached: skippedCached,
          downloaded: downloaded,
          failed: failed,
          addedBytes: addedBytes,
        ),
        currentTerm: currentTerm,
        scopeLabel: scopeLabel,
      );
}
