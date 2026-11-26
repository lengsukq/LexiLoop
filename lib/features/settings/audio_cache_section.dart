/// 设置页「播放」分组里的离线语音缓存管理卡片。
///
/// 展示有道/Edge 分项缓存占用、容量上限与自动淘汰、分桶/全量清理，
/// 以及词库一键离线预缓存的实时进度。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/audio_cache_providers.dart';
import 'package:lexiloop/features/settings/audio_precache_sheet.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/audio/audio_precache_service.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 清空全部离线语音缓存二次确认按钮 Key。
const Key clearAllAudioCacheConfirmKey = Key('clearAllAudioCacheConfirm');

/// 离线语音缓存管理分组卡片。
class AudioCacheSection extends ConsumerWidget {
  /// 以当前播放设置构造。
  const new({required this.playback, super.key});

  /// 当前播放设置。
  final PlaybackSettings playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disk = ref.watch(speechDiskCacheProvider);
    if (!disk.isSupported) {
      return const SettingsSectionCard(
        title: '离线语音缓存',
        subtitle: '当前浏览器环境仅保留会话内内存缓存，关闭页面后自动释放。',
        child: SizedBox.shrink(),
      );
    }
    final stats =
        ref.watch(speechCacheStatsProvider).value ?? SpeechCacheStats.empty;
    final precache = ref.watch(audioPrecacheControllerProvider);

    return SettingsSectionCard(
      title: '离线语音缓存',
      subtitle: '播过的在线语音会保存在本机，断网也能秒放；支持按需提前缓存整本词书与分项清理。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CacheUsageMeter(stats: stats, maxBytes: playback.audioCacheMaxBytes),
          const SizedBox(height: LexiSpace.s10),
          _BucketUsageRow(
            bucket: SpeechCacheBucket.youdao,
            files: stats.youdaoFiles,
            bytes: stats.youdaoBytes,
            busy: precache.isActive,
          ),
          const SizedBox(height: LexiSpace.s6),
          _BucketUsageRow(
            bucket: SpeechCacheBucket.edge,
            files: stats.edgeFiles,
            bytes: stats.edgeBytes,
            busy: precache.isActive,
          ),
          const SizedBox(height: LexiSpace.s12),
          _CachePolicyControls(playback: playback),
          if (precache.status != AudioPrecacheStatus.idle) ...<Widget>[
            const SizedBox(height: LexiSpace.s12),
            _PrecacheStatusBanner(progress: precache),
          ],
          const SizedBox(height: LexiSpace.s12),
          _CacheActionBar(stats: stats, precache: precache),
        ],
      ),
    );
  }
}

class _CacheUsageMeter extends StatelessWidget {
  const new({required this.stats, required this.maxBytes});

  final SpeechCacheStats stats;
  final int maxBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final usedText = formatBackupBytes(stats.totalBytes);
    final limitText = maxBytes <= 0 ? '不限制' : formatBackupBytes(maxBytes);
    final ratio = maxBytes <= 0
        ? 0.0
        : (stats.totalBytes / maxBytes).clamp(0.0, 1.0);
    final nearFull = maxBytes > 0 && ratio >= audioCacheEvictTargetRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '已占用 $usedText / $limitText',
                key: const Key('audioCacheTotalUsage'),
                style: LexiType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.label,
                ),
              ),
            ),
            Text(
              '共 ${stats.totalFiles} 条',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
        if (maxBytes > 0) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          ClipRRect(
            borderRadius: BorderRadius.circular(LexiRadius.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: LexiSpace.s6,
              color: nearFull ? colors.warning : colors.accent,
            ),
          ),
        ],
      ],
    );
  }
}

class _BucketUsageRow extends ConsumerWidget {
  const new({
    required this.bucket,
    required this.files,
    required this.bytes,
    required this.busy,
  });

  final SpeechCacheBucket bucket;
  final int files;
  final int bytes;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s12,
          vertical: LexiSpace.s8,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    bucket.label,
                    style: LexiType.footnote.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.label,
                    ),
                  ),
                  Text(
                    '$files 条 · ${formatBackupBytes(bytes)}',
                    key: Key('audioCacheBucket_${bucket.folder}'),
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: Key('clearSpeechBucket_${bucket.folder}'),
              onPressed: busy || files == 0
                  ? null
                  : () => unawaited(_clearOne(context, ref)),
              child: const Text('清理'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearOne(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await clearSpeechCache(ref, bucket: bucket);
    messenger?.showSnackBar(SnackBar(content: Text('已清理「${bucket.label}」缓存')));
  }
}

class _CachePolicyControls extends ConsumerWidget {
  const new({required this.playback});

  final PlaybackSettings playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = <int>[
      ...audioCacheMaxSizeOptionsMb,
      if (!audioCacheMaxSizeOptionsMb.contains(playback.audioCacheMaxSizeMb))
        playback.audioCacheMaxSizeMb,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSwitchRow(
          switchKey: const Key('playbackOfflineAudioCache'),
          label: '开启离线语音持久化缓存',
          description: '关闭后仅保留当前会话的内存缓存，重启应用后需重新联网拉取。',
          value: playback.offlineAudioCacheEnabled,
          onChanged: (value) => saveSettings(ref, <String, Object?>{
            'offlineAudioCacheEnabled': value,
          }),
        ),
        const SizedBox(height: LexiSpace.s8),
        DropdownButtonFormField<int>(
          key: const Key('playbackAudioCacheLimit'),
          initialValue: playback.audioCacheMaxSizeMb,
          decoration: const InputDecoration(
            labelText: '最大缓存空间',
            helperText: '超过上限时自动清理最久未播放的旧音频。',
          ),
          items: <DropdownMenuItem<int>>[
            for (final mb in options)
              DropdownMenuItem<int>(value: mb, child: Text(_limitLabel(mb))),
          ],
          onChanged: (nextMb) {
            if (nextMb == null) return;
            unawaited(_updateLimit(context, ref, nextMb));
          },
        ),
      ],
    );
  }

  Future<void> _updateLimit(
    BuildContext context,
    WidgetRef ref,
    int nextMb,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await saveSettings(ref, <String, Object?>{'audioCacheMaxSizeMb': nextMb});
    if (nextMb <= 0) return;
    final removed = await enforceSpeechCacheLimit(
      ref,
      nextMb * audioCacheBytesPerMb,
    );
    if (removed > 0) {
      messenger?.showSnackBar(
        SnackBar(content: Text('已按新上限自动清理 $removed 条最久未用的旧语音缓存')),
      );
    }
  }

  String _limitLabel(int mb) {
    if (mb <= 0) return '不限制';
    if (mb >= 1024 && mb % 1024 == 0) return '${mb ~/ 1024} GB';
    return '$mb MB';
  }
}

class _PrecacheStatusBanner extends ConsumerWidget {
  const new({required this.progress});

  final AudioPrecacheProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final counts = progress.counts;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _bannerHeader(context, ref),
            if (progress.isActive) ...<Widget>[
              const SizedBox(height: LexiSpace.s6),
              ClipRRect(
                borderRadius: BorderRadius.circular(LexiRadius.pill),
                child: LinearProgressIndicator(
                  value: progress.status == AudioPrecacheStatus.scanning
                      ? null
                      : counts.fraction,
                  minHeight: LexiSpace.s6,
                ),
              ),
            ],
            const SizedBox(height: LexiSpace.s6),
            Text(
              _detailText(counts),
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerHeader(BuildContext context, WidgetRef ref) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          _titleText(),
          style: LexiType.footnote.copyWith(
            fontWeight: FontWeight.w600,
            color: context.lexiColors.label,
          ),
        ),
      ),
      if (progress.isActive)
        TextButton(
          key: const Key('audioPrecacheCancelButton'),
          onPressed: () =>
              ref.read(audioPrecacheControllerProvider.notifier).cancel(),
          child: const Text('停止'),
        )
      else
        IconButton(
          tooltip: '关闭提示',
          iconSize: 16,
          onPressed: () =>
              ref.read(audioPrecacheControllerProvider.notifier).resetNotice(),
          icon: const Icon(LucideIcons.x),
        ),
    ],
  );

  String _titleText() {
    final counts = progress.counts;
    return switch (progress.status) {
      AudioPrecacheStatus.scanning => '正在扫描「${progress.scopeLabel}」…',
      AudioPrecacheStatus.running =>
        '正在缓存「${progress.scopeLabel}」(${counts.processed}/${counts.total})',
      AudioPrecacheStatus.cancelling => '正在停止缓存…',
      AudioPrecacheStatus.completed => '离线缓存完成（${progress.scopeLabel}）',
      AudioPrecacheStatus.cancelled => '已暂停缓存（已落盘项已保留，下次自动续传）',
      AudioPrecacheStatus.idle => '',
    };
  }

  String _detailText(AudioPrecacheCounts counts) {
    final addedLabel = counts.addedBytes > 0
        ? ' · +${formatBackupBytes(counts.addedBytes)}'
        : '';
    final failedLabel = counts.failed > 0 ? ' · 失败 ${counts.failed}' : '';
    return '新下载 ${counts.downloaded} · 已跳过 ${counts.skippedCached}'
        '$failedLabel$addedLabel';
  }
}

class _CacheActionBar extends ConsumerWidget {
  const new({required this.stats, required this.precache});

  final SpeechCacheStats stats;
  final AudioPrecacheProgress precache;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: LexiSpace.s8,
    runSpacing: LexiSpace.s8,
    children: <Widget>[
      OutlinedButton.icon(
        key: const Key('playbackOpenPrecache'),
        onPressed: precache.isActive
            ? null
            : () => unawaited(showAudioPrecacheSheet(context, ref)),
        icon: const Icon(LucideIcons.cloudDownload, size: 16),
        label: const Text('离线缓存词库发音'),
      ),
      TextButton.icon(
        onPressed: () => ref.invalidate(speechCacheStatsProvider),
        icon: const Icon(LucideIcons.refreshCw, size: 16),
        label: const Text('刷新统计'),
      ),
      TextButton.icon(
        key: const Key('playbackClearAllAudioCache'),
        onPressed: precache.isActive || stats.totalFiles == 0
            ? null
            : () => unawaited(_confirmClearAll(context, ref)),
        icon: const Icon(LucideIcons.trash2, size: 16),
        label: const Text('清空全部缓存'),
      ),
    ],
  );

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showLexiConfirmSheet(
      context,
      title: '清空全部离线语音缓存？',
      body:
          '将删除本机已缓存的 ${stats.totalFiles} 条语音 '
          '（${formatBackupBytes(stats.totalBytes)}），不影响词条和学习进度。',
      confirmLabel: '清空',
      destructive: true,
      confirmButtonKey: clearAllAudioCacheConfirmKey,
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await clearSpeechCache(ref);
    messenger?.showSnackBar(const SnackBar(content: Text('已清空全部离线语音缓存')));
  }
}
