/// 离线缓存词库发音的范围与口音选择弹窗。
///
/// 由「设置 → 播放 → 离线语音缓存」与「词书包」已安装卡片共同复用。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/features/settings/audio_cache_providers.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/services/audio/audio_precache_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 拉起批量离线缓存配置弹窗；开始任务后返回 `true`。
Future<bool> showAudioPrecacheSheet(
  BuildContext context,
  WidgetRef ref, {
  String? initialPackId,
  String? initialPackName,
}) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AudioPrecacheSheet(
      initialPackId: initialPackId,
      initialPackName: initialPackName,
    ),
  );
  return started ?? false;
}

class _AudioPrecacheSheet extends ConsumerStatefulWidget {
  const new({this.initialPackId, this.initialPackName});

  final String? initialPackId;
  final String? initialPackName;

  @override
  ConsumerState<_AudioPrecacheSheet> createState() =>
      _AudioPrecacheSheetState();
}

class _AudioPrecacheSheetState extends ConsumerState<_AudioPrecacheSheet> {
  late String _selectedScopeKey;
  AudioPrecacheAccentMode _accentMode = AudioPrecacheAccentMode.defaultOnly;
  bool _includeEdge = false;
  AudioPrecacheEstimate? _estimate;
  bool _loadingEstimate = true;

  @override
  void initState() {
    super.initState();
    _selectedScopeKey = widget.initialPackId != null
        ? 'pack:${widget.initialPackId}'
        : 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEstimate());
  }

  AudioPrecacheScope _resolveScope(List<InstalledWordPackSummary> packs) {
    if (_selectedScopeKey == 'personal') return AudioPrecacheScope.personalOnly;
    if (_selectedScopeKey.startsWith('pack:')) {
      final packId = _selectedScopeKey.substring(5);
      for (final pack in packs) {
        if (pack.id == packId) {
          return AudioPrecacheScope.wordPack(
            packId: pack.id,
            packName: pack.name,
          );
        }
      }
      return AudioPrecacheScope.wordPack(
        packId: packId,
        packName: widget.initialPackName ?? packId,
      );
    }
    return AudioPrecacheScope.allWords;
  }

  Future<void> _refreshEstimate() async {
    if (!mounted) return;
    setState(() => _loadingEstimate = true);
    final playback =
        ref.read(appSettingsProvider).value?.playback ??
        PlaybackSettings.defaults;
    final packs =
        ref.read(installedWordPacksProvider).value ??
        const <InstalledWordPackSummary>[];
    final estimate = await ref
        .read(audioPrecacheServiceProvider)
        .estimate(
          scope: _resolveScope(packs),
          accentMode: _accentMode,
          defaultAccent: playback.defaultAccent,
          includeEdgeFallback: _includeEdge,
        );
    if (!mounted) return;
    setState(() {
      _estimate = estimate;
      _loadingEstimate = false;
    });
  }

  void _start(List<InstalledWordPackSummary> packs, PlaybackSettings playback) {
    final request = AudioPrecacheRequest(
      scope: _resolveScope(packs),
      accentMode: _accentMode,
      defaultAccent: playback.defaultAccent,
      maxCacheBytes: playback.audioCacheMaxBytes,
      includeEdgeFallback: _includeEdge,
    );
    unawaited(
      ref.read(audioPrecacheControllerProvider.notifier).start(request),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final playback =
        ref.watch(appSettingsProvider).value?.playback ??
        PlaybackSettings.defaults;
    final packs =
        ref.watch(installedWordPacksProvider).value ??
        const <InstalledWordPackSummary>[];
    final items = _scopeItems(packs);
    final currentKey = items.any((item) => item.value == _selectedScopeKey)
        ? _selectedScopeKey
        : 'all';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        LexiSpace.s20,
        LexiSpace.s16,
        LexiSpace.s20,
        LexiSpace.s20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('离线缓存词库发音', style: LexiType.title.copyWith(color: colors.label)),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '提前把单词真人 MP3 存到手机本地；已缓存的词条会自动跳过，支持随时停止与断点续传。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s16),
          DropdownButtonFormField<String>(
            key: const Key('audioPrecacheScope'),
            initialValue: currentKey,
            decoration: const InputDecoration(labelText: '缓存范围'),
            items: items,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedScopeKey = value);
              unawaited(_refreshEstimate());
            },
          ),
          const SizedBox(height: LexiSpace.s12),
          _AccentSelector(
            mode: _accentMode,
            onChanged: (next) {
              setState(() => _accentMode = next);
              unawaited(_refreshEstimate());
            },
          ),
          const SizedBox(height: LexiSpace.s8),
          SettingsSwitchRow(
            switchKey: const Key('audioPrecacheIncludeEdge'),
            label: '同时用 Edge 补全整句与有道缺失词',
            description: '默认仅缓存有道单词与短语（速度最快）；开启后会额外调用 Edge，耗时较长。',
            value: _includeEdge,
            onChanged: (value) {
              setState(() => _includeEdge = value);
              unawaited(_refreshEstimate());
            },
          ),
          const SizedBox(height: LexiSpace.s8),
          _EstimateSummary(
            loading: _loadingEstimate,
            estimate: _estimate,
            maxCacheBytes: playback.audioCacheMaxBytes,
          ),
          const SizedBox(height: LexiSpace.s16),
          _SheetFooter(
            canStart: !_loadingEstimate && (_estimate?.itemCount ?? 0) > 0,
            onCancel: () => Navigator.of(context).pop(false),
            onStart: () => _start(packs, playback),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _scopeItems(
    List<InstalledWordPackSummary> packs,
  ) => <DropdownMenuItem<String>>[
    const DropdownMenuItem<String>(value: 'all', child: Text('全部词条')),
    const DropdownMenuItem<String>(value: 'personal', child: Text('仅个人词库')),
    for (final pack in packs)
      DropdownMenuItem<String>(
        value: 'pack:${pack.id}',
        child: Text('词书：${pack.name}（${pack.totalWords} 词）'),
      ),
    if (widget.initialPackId != null &&
        !packs.any((p) => p.id == widget.initialPackId))
      DropdownMenuItem<String>(
        value: 'pack:${widget.initialPackId}',
        child: Text('词书：${widget.initialPackName ?? widget.initialPackId}'),
      ),
  ];
}

class _SheetFooter extends StatelessWidget {
  const new({
    required this.canStart,
    required this.onCancel,
    required this.onStart,
  });

  final bool canStart;
  final VoidCallback onCancel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: OutlinedButton(onPressed: onCancel, child: const Text('取消')),
      ),
      const SizedBox(width: LexiSpace.s12),
      Expanded(
        child: FilledButton.icon(
          key: const Key('audioPrecacheStartButton'),
          onPressed: canStart ? onStart : null,
          icon: const Icon(LucideIcons.download, size: 16),
          label: const Text('开始缓存'),
        ),
      ),
    ],
  );
}

class _AccentSelector extends StatelessWidget {
  const new({required this.mode, required this.onChanged});

  final AudioPrecacheAccentMode mode;
  final ValueChanged<AudioPrecacheAccentMode> onChanged;

  @override
  Widget build(BuildContext context) =>
      SegmentedButton<AudioPrecacheAccentMode>(
        segments: const <ButtonSegment<AudioPrecacheAccentMode>>[
          ButtonSegment<AudioPrecacheAccentMode>(
            value: AudioPrecacheAccentMode.defaultOnly,
            label: Text('仅默认口音'),
          ),
          ButtonSegment<AudioPrecacheAccentMode>(
            value: AudioPrecacheAccentMode.bothUsAndUk,
            label: Text('美音 + 英音'),
          ),
        ],
        selected: <AudioPrecacheAccentMode>{mode},
        onSelectionChanged: (selection) => onChanged(selection.first),
      );
}

class _EstimateSummary extends StatelessWidget {
  const new({
    required this.loading,
    required this.estimate,
    required this.maxCacheBytes,
  });

  final bool loading;
  final AudioPrecacheEstimate? estimate;
  final int maxCacheBytes;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    if (loading || estimate == null) {
      return Text(
        '正在统计待缓存词条…',
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      );
    }
    final count = estimate!.itemCount;
    if (count == 0) {
      return Text(
        '当前范围内暂无可缓存的英文单词或短语。',
        style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      );
    }
    final bytesText = formatBackupBytes(estimate!.estimatedBytes);
    final exceeds =
        maxCacheBytes > 0 && estimate!.estimatedBytes > maxCacheBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '共扫描 $count 条语音，预估占用 ≤ $bytesText（已落盘条目自动跳过）。',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        if (exceeds)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s4),
            child: Text(
              '预估体积超过当前缓存上限（${formatBackupBytes(maxCacheBytes)}），'
              '建议先调大上限以免较早缓存被自动淘汰。',
              style: LexiType.caption.copyWith(color: colors.warningText),
            ),
          ),
      ],
    );
  }
}
