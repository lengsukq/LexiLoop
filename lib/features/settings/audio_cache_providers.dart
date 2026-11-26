/// 离线语音缓存统计、清理与批量预缓存的 Riverpod 编排。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/services/audio/audio_precache_service.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

/// 当前离线语音磁盘缓存的分桶统计。
final FutureProvider<SpeechCacheStats> speechCacheStatsProvider =
    FutureProvider<SpeechCacheStats>(
      (ref) => ref.watch(speechDiskCacheProvider).stats(),
    );

/// 词库离线语音批量预缓存任务控制器。
class AudioPrecacheController extends Notifier<AudioPrecacheProgress> {
  bool _cancelRequested = false;

  @override
  AudioPrecacheProgress build() => AudioPrecacheProgress.idle;

  /// 启动一轮批量预缓存；若已有任务在跑则忽略重复触发。
  Future<void> start(AudioPrecacheRequest request) async {
    if (state.isActive) return;
    _cancelRequested = false;
    final service = ref.read(audioPrecacheServiceProvider);
    await service.run(
      request,
      onProgress: (progress) => state = progress,
      isCancelled: () => _cancelRequested,
    );
    ref.invalidate(speechCacheStatsProvider);
  }

  /// 请求中止当前批量预缓存（已落盘音频保留，下次可续传）。
  void cancel() {
    if (!state.isActive) return;
    _cancelRequested = true;
    state = AudioPrecacheProgress(
      status: AudioPrecacheStatus.cancelling,
      counts: state.counts,
      currentTerm: state.currentTerm,
      scopeLabel: state.scopeLabel,
    );
  }

  /// 收起已完成/已取消的结果提示条。
  void resetNotice() {
    if (state.isActive) return;
    state = AudioPrecacheProgress.idle;
  }
}

/// 批量预缓存状态 provider。
final NotifierProvider<AudioPrecacheController, AudioPrecacheProgress>
audioPrecacheControllerProvider =
    NotifierProvider<AudioPrecacheController, AudioPrecacheProgress>(
      AudioPrecacheController.new,
    );

/// 清空指定引擎分桶（或全部）的磁盘与内存缓存，并刷新统计视图。
Future<void> clearSpeechCache(
  WidgetRef ref, {
  SpeechCacheBucket? bucket,
}) async {
  await ref.read(speechDiskCacheProvider).clear(bucket: bucket);
  if (bucket == null || bucket == SpeechCacheBucket.youdao) {
    ref.read(audioCacheProvider).clear();
  }
  if (bucket == null || bucket == SpeechCacheBucket.edge) {
    final edge = ref.read(directEdgeSpeechProvider);
    if (edge is DirectEdgeSpeech) edge.clearMemoryCache();
  }
  ref.invalidate(speechCacheStatsProvider);
}

/// 立即按新容量上限执行一次 LRU 裁剪并返回清理的文件数。
Future<int> enforceSpeechCacheLimit(WidgetRef ref, int maxBytes) async {
  final removed = await ref
      .read(speechDiskCacheProvider)
      .enforceLimit(maxBytes);
  ref.invalidate(speechCacheStatsProvider);
  return removed;
}
