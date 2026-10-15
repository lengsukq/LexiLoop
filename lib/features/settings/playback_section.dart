/// 播放设置分组。
///
/// 口音、三种粒度的语速、自动朗读与选择题揭示延迟。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';

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
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
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
