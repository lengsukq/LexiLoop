/// 播放设置分组。
///
/// 口音、真人录音来源、三种粒度的语速、自动朗读与选择题揭示延迟。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

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
        SettingsSectionCard(
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
                description: '进入题目时自动播放词条发音。',
                value: playback.autoPlayPronunciation,
                onChanged: (value) => saveSettings(ref, <String, Object?>{
                  'autoPlayPronunciation': value,
                }),
              ),
            ],
          ),
        ),
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

/// 发音来源分组：口音与「优先真人录音」。
///
/// 两项放在同一个私有组件里，因为它们回答的是同一个问题——「这个声音从哪来」：
/// 口音决定用美音还是英音，真人录音开关决定优先用词典的录音还是系统朗读。
/// 拆成组件还有一个硬性理由：`PlaybackSection.build()` 已接近架构守卫的
/// 80 行上限，再往列表里塞一张卡片就会越线。
///
/// **「优先使用词典真人发音」是相对旧版新增的开关**：旧版
/// `src/app/(main)/settings/` 下的播放设置只有口音、语速与自动朗读，
/// 发音链路固定为「真人录音优先」，用户无从选择。本版把它做成运行时开关，
/// 理由是这条链路依赖第三方词典站点：站点不可用时要能一键回到系统朗读，
/// 用户不想为每次点按付一次网络请求时也不该被迫改代码。
/// 写入的键就是 [PlaybackSettings.humanAudioEnabled]（`humanAudioEnabled`），
/// 消费方是 `services/audio/word_speaker.dart` 的运行时开关字段。
class _PronunciationGroup extends ConsumerWidget {
  const new({required this.playback});

  /// 当前播放设置。
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
        title: '真人录音',
        subtitle: '词典站点提供的是真人朗读的 mp3，音质明显好于系统合成音，代价是每次播放都要联网取一次。',
        child: SettingsSwitchRow(
          switchKey: const Key('playbackHumanAudio'),
          label: '优先使用词典真人发音',
          description:
              '开启后优先播放词典的真人录音，站点不可用时自动回落系统朗读；'
              '关闭后只用系统朗读，完全不联网。',
          value: playback.humanAudioEnabled,
          onChanged: (value) =>
              saveSettings(ref, <String, Object?>{'humanAudioEnabled': value}),
        ),
      ),
    ],
  );
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
