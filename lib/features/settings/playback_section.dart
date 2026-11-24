/// 播放设置分组。
///
/// 口音、多选与拖拽排序的发音优先级链、三种粒度的语速、自动朗读与选择题揭示延迟。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/audio_cache_section.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/tts_settings_link.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 播放分组。
class PlaybackSection extends ConsumerWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前设置。
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = settings.playback;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
      children: <Widget>[
        _PronunciationGroup(playback: playback),
        const SizedBox(height: LexiSpace.s12),
        AudioCacheSection(playback: playback),
        const SizedBox(height: LexiSpace.s12),
        _ChoiceStyleGroup(playback: playback),
        const SizedBox(height: LexiSpace.s12),
        _SpeechSpeedGroup(playback: playback),
        const SizedBox(height: LexiSpace.s12),
        SettingsSectionCard(
          title: '选择题',
          subtitle: '揭示答案前的延迟，留出回忆时间。',
          child: SettingsSliderRow(
            key: const Key('playbackRevealDelay'),
            label: '揭示延迟',
            valueText: '${playback.choiceRevealDelaySeconds} 秒',
            value: playback.choiceRevealDelaySeconds.toDouble(),
            min: 0,
            max: maxChoiceRevealDelaySeconds.toDouble(),
            divisions: maxChoiceRevealDelaySeconds,
            onChangeEnd: (value) => saveSettings(ref, <String, Object?>{
              'choiceRevealDelaySeconds': value.round(),
            }),
          ),
        ),
      ],
    );
  }
}

/// 释义卡片长度设置，与声音选项解耦。
class _ChoiceStyleGroup extends ConsumerWidget {
  const new({required this.playback});

  final PlaybackSettings playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSectionCard(
    title: '学习选项',
    subtitle: '只改变选项文字的长度，不影响正确答案、判题或词条原文。',
    child: DropdownButtonFormField<ChoiceDefinitionStyle>(
      key: const Key('playbackChoiceDefinitionStyle'),
      initialValue: playback.choiceDefinitionStyle,
      decoration: const InputDecoration(labelText: '释义详细程度'),
      items: <DropdownMenuItem<ChoiceDefinitionStyle>>[
        for (final style in ChoiceDefinitionStyle.values)
          DropdownMenuItem(value: style, child: Text(style.label)),
      ],
      onChanged: (style) {
        if (style == null) return;
        unawaited(
          saveSettings(ref, <String, Object?>{
            'choiceDefinitionStyle': style.wire,
          }),
        );
      },
    ),
  );
}

/// 分别调节词、短语、句子的朗读语速。
class _SpeechSpeedGroup extends ConsumerWidget {
  const new({required this.playback});

  final PlaybackSettings playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSectionCard(
    title: '朗读语速',
    subtitle: '按词条长度分开设置：句子读太快会听不清，单词读太慢会浪费时间。',
    child: Column(
      children: <Widget>[
        _SpeedSlider(
          sliderKey: const Key('playbackWordSpeed'),
          label: '单词语速',
          value: playback.wordSpeed,
          keyName: 'wordSpeed',
        ),
        _SpeedSlider(
          sliderKey: const Key('playbackPhraseSpeed'),
          label: '短语语速',
          value: playback.phraseSpeed,
          keyName: 'phraseSpeed',
        ),
        _SpeedSlider(
          sliderKey: const Key('playbackSentenceSpeed'),
          label: '句子语速',
          value: playback.sentenceSpeed,
          keyName: 'sentenceSpeed',
        ),
        SettingsSwitchRow(
          label: '自动朗读',
          description: !playback.speechEnabled
              ? '当前所有发音引擎均已关闭，请先在上方启用至少一项。'
              : '英文题进入时自动朗读；拼写、中文提示等题型揭示答案后朗读。',
          value: playback.autoPlayPronunciation,
          onChanged: (value) => saveSettings(ref, <String, Object?>{
            'autoPlayPronunciation': value,
          }),
        ),
      ],
    ),
  );
}

/// 口音与发音引擎优先级链配置。
class _PronunciationGroup extends ConsumerWidget {
  const new({required this.playback});

  final PlaybackSettings playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: <Widget>[
      SettingsSectionCard(
        title: '默认口音',
        subtitle: '影响自动朗读与听力题使用哪一套发音。',
        child: Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<Accent>(
            segments: const <ButtonSegment<Accent>>[
              ButtonSegment<Accent>(value: Accent.us, label: Text('美音 US')),
              ButtonSegment<Accent>(value: Accent.uk, label: Text('英音 UK')),
            ],
            selected: <Accent>{playback.defaultAccent},
            onSelectionChanged: (selection) => saveSettings(
              ref,
              <String, Object?>{'defaultAccent': selection.first.wire},
            ),
          ),
        ),
      ),
      const SizedBox(height: LexiSpace.s12),
      SettingsSectionCard(
        title: '发音引擎与优先级',
        subtitle: '可多选启用，拖动右侧手柄调整顺序；排在前面的不可用时，自动顺延到下一项。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SpeechChainEditor(playback: playback),
            const SizedBox(height: LexiSpace.s12),
            Wrap(
              spacing: LexiSpace.s8,
              runSpacing: LexiSpace.s8,
              children: <Widget>[
                OutlinedButton.icon(
                  key: const Key('playbackTestSpeech'),
                  onPressed: () => unawaited(_testSpeech(context, ref)),
                  icon: const Icon(LucideIcons.play, size: 16),
                  label: const Text('试听发音'),
                ),
                TextButton.icon(
                  key: const Key('playbackDiagnoseSpeech'),
                  onPressed: () => unawaited(_diagnoseAll(context, ref)),
                  icon: const Icon(LucideIcons.activity, size: 16),
                  label: const Text('引擎检测'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(openSystemSpeechSettings(context)),
                  icon: const Icon(LucideIcons.settings, size: 16),
                  label: const Text('系统语音设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _testSpeech(BuildContext context, WidgetRef ref) async {
    final latest = await ref.read(settingsServiceProvider).load();
    if (!context.mounted) return;
    final selected = latest.playback;
    final result = await ref
        .read(wordSpeakerProvider)
        .speak(
          SpeechRequest(
            term: 'hello',
            accent: selected.defaultAccent,
            playback: selected,
          ),
        );
    if (!context.mounted) return;
    final message = switch (result) {
      SpeechDisabled() => '当前已关闭所有发音引擎，请先开启至少一项',
      SpeechFailed(:final error) => '试听失败：${error.message}。请检查网络或系统语音包。',
      _ when result.fellBack =>
        '${result.fellBackFrom!.label}暂不可用，已自动切换为${result.playedSource!.label}',
      _ => '试听成功：${result.playedSource!.label}',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _diagnoseAll(BuildContext context, WidgetRef ref) async {
    final report = await _collectDiagnostics(ref);
    if (!context.mounted) return;
    await _showDiagnosticsDialog(context, report);
  }

  Future<String> _collectDiagnostics(WidgetRef ref) async {
    final playback = (await ref.read(settingsServiceProvider).load()).playback;
    final accent = playback.defaultAccent;
    final results = await Future.wait<String>(<Future<String>>[
      _probeYoudao(ref, accent),
      _probeEdge(accent),
      _probeSystem(ref, accent),
    ]);
    return <String>['发音引擎检测 · hello（${accent.wire}）', ...results].join('\n');
  }

  Future<String> _probeYoudao(WidgetRef ref, Accent accent) async {
    final watch = Stopwatch()..start();
    try {
      final url = youdaoAudioUri('hello', accent)!;
      final bytes = await ref.read(audioDownloaderProvider).download(url);
      watch.stop();
      return '• 有道词典发音：正常（${bytes.length} 字节，${watch.elapsedMilliseconds}ms）';
    } on Object catch (error) {
      watch.stop();
      return '• 有道词典发音：失败（${watch.elapsedMilliseconds}ms，${error.runtimeType}）';
    }
  }

  Future<String> _probeEdge(Accent accent) async {
    final watch = Stopwatch()..start();
    try {
      final bytes = await DirectEdgeSpeech().diagnose(
        text: 'hello',
        accent: accent,
      );
      watch.stop();
      final ms = watch.elapsedMilliseconds;
      return '• 微软 Edge 语音：正常（${bytes.length} 字节，${ms}ms）';
    } on Object catch (error) {
      watch.stop();
      final ms = watch.elapsedMilliseconds;
      return '• 微软 Edge 语音：失败（${ms}ms，${error.runtimeType}）';
    }
  }

  Future<String> _probeSystem(WidgetRef ref, Accent accent) async {
    try {
      final language = speechLanguageOf(accent);
      final available = await ref
          .read(ttsServiceProvider)
          .isLanguageAvailable(language);
      return available
          ? '• 设备系统朗读：正常（已安装 $language 语音包）'
          : '• 设备系统朗读：缺少 $language 语音包，请在系统语音设置中安装';
    } on Object catch (error) {
      return '• 设备系统朗读：检测失败（${error.runtimeType}）';
    }
  }

  Future<void> _showDiagnosticsDialog(BuildContext context, String report) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('发音引擎检测结果'),
          content: SelectableText(report),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('复制结果'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
}

/// 可多选且可拖动排序的发音引擎列表。
class _SpeechChainEditor extends ConsumerWidget {
  const new({required this.playback});

  final PlaybackSettings playback;

  Future<void> _saveChain(WidgetRef ref, List<SpeechSourcePreference> next) =>
      saveSettings(ref, <String, Object?>{
        'speechChain': PlaybackSettings.serializeSpeechChain(next),
      });

  void _toggle(WidgetRef ref, SpeechSource source, bool enabled) {
    LexiHaptics.selection();
    final next = <SpeechSourcePreference>[
      for (final item in playback.speechChain)
        if (item.source == source) item.copyWith(enabled: enabled) else item,
    ];
    unawaited(_saveChain(ref, next));
  }

  void _reorder(WidgetRef ref, int oldIndex, int newIndex) {
    if (newIndex == oldIndex) return;
    LexiHaptics.selection();
    final next = List<SpeechSourcePreference>.of(playback.speechChain);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    unawaited(_saveChain(ref, next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chain = playback.speechChain;
    final colors = context.lexiColors;
    var activeRank = 0;
    final ranks = <int?>[
      for (final item in chain)
        if (item.enabled) ++activeRank else null,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ReorderableListView.builder(
          key: const Key('playbackSpeechChain'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          proxyDecorator: _dragProxyDecorator,
          itemCount: chain.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorder(ref, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final entry = chain[index];
            return _SpeechSourceTile(
              key: ValueKey<SpeechSource>(entry.source),
              entry: entry,
              index: index,
              rank: ranks[index],
              onToggle: (value) => _toggle(ref, entry.source, value),
            );
          },
        ),
        if (!playback.speechEnabled)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s6),
            child: Text(
              '所有发音引擎均已关闭（当前为静音模式）。',
              style: LexiType.footnote.copyWith(color: colors.warningText),
            ),
          ),
      ],
    );
  }

  Widget _dragProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) => Material(
    color: Colors.transparent,
    elevation: LexiSpace.s4,
    borderRadius: BorderRadius.circular(LexiRadius.md),
    child: child,
  );
}

/// 优先级链中的单条发音引擎行。
class _SpeechSourceTile extends StatelessWidget {
  const new({
    required this.entry,
    required this.index,
    required this.rank,
    required this.onToggle,
    super.key,
  });

  final SpeechSourcePreference entry;
  final int index;
  final int? rank;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final enabled = entry.enabled;
    final borderColor = enabled ? colors.borderDefault : colors.borderSubtle;
    final fillColor = enabled ? colors.card : colors.fill;

    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s12,
            vertical: LexiSpace.s10,
          ),
          child: Row(
            children: <Widget>[
              _RankBadge(rank: rank),
              const SizedBox(width: LexiSpace.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.source.label,
                      style: LexiType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled ? colors.label : colors.tertiaryLabel,
                      ),
                    ),
                    const SizedBox(height: LexiSpace.s2),
                    Text(
                      entry.source.description,
                      style: LexiType.footnote.copyWith(
                        color: enabled
                            ? colors.secondaryLabel
                            : colors.tertiaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              Switch(
                key: Key('speechSourceToggle_${entry.source.wire}'),
                value: enabled,
                onChanged: onToggle,
              ),
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: '拖动调整优先级',
                  child: Padding(
                    padding: const EdgeInsets.all(LexiSpace.s8),
                    child: Icon(
                      LucideIcons.gripVertical,
                      key: Key('speechSourceDrag_${entry.source.wire}'),
                      size: 18,
                      color: colors.tertiaryLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 优先级顺位徽章（已启用显示 1 / 2 / 3，关闭显示 —）。
class _RankBadge extends StatelessWidget {
  const new({required this.rank});

  final int? rank;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final active = rank != null;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? colors.accent : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.pill),
      ),
      child: Text(
        active ? '$rank' : '—',
        style: LexiType.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: active
              ? Theme.of(context).colorScheme.onPrimary
              : colors.tertiaryLabel,
        ),
      ),
    );
  }
}

/// 语速滑条（三种粒度共用同一区间）。
class _SpeedSlider extends ConsumerWidget {
  const new({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.keyName,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final String keyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSliderRow(
      key: sliderKey,
      label: label,
      valueText: '${value.toStringAsFixed(2)}×',
      value: value,
      min: minSpeechRate,
      max: maxSpeechRate,
      divisions: _speedSteps,
      onChangeEnd: (next) => saveSettings(ref, <String, Object?>{
        keyName: double.parse(next.toStringAsFixed(2)),
      }),
    );
  }
}

/// 语速滑条刻度：按 0.05 一档。
final int _speedSteps = ((maxSpeechRate - minSpeechRate) / 0.05).round();
