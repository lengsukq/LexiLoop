/// 播放设置分组。
///
/// 口音、真人录音来源、三种粒度的语速、自动朗读与选择题揭示延迟。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/next_tts_auth.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/tts_settings_link.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';

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
          description: playback.speechSource == SpeechSource.off
              ? '当前发音来源已设为「关闭发音」，请先在上方启用发音。'
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

/// 用户自行部署的 Next.js 服务地址，按按钮才落库，避免输入过程中逐字写库。
class _OnlineTtsAddressField extends ConsumerStatefulWidget {
  const new({required this.value});

  final String value;

  @override
  ConsumerState<_OnlineTtsAddressField> createState() =>
      _OnlineTtsAddressFieldState();
}

class _OnlineTtsAddressFieldState
    extends ConsumerState<_OnlineTtsAddressField> {
  late final TextEditingController _controller;
  final TextEditingController _password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_OnlineTtsAddressField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.text == oldWidget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = _controller.text.trim().replaceAll(
      RegExp(
        '/'
        r'$',
      ),
      '',
    );
    final valid =
        input.isEmpty ||
        onlineTtsAudioUri(baseUrl: input, term: 'hello', accent: Accent.us) !=
            null;
    if (!valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入 Next.js 的 HTTPS 根地址，例如 https://example.com'),
        ),
      );
      return;
    }
    await saveSettings(ref, <String, Object?>{'onlineTtsBaseUrl': input});
    if (_password.text.isNotEmpty) {
      await NextTtsCredentials().save(_password.text);
      _password.clear();
    }
    if (mounted) FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      TextField(
        key: const Key('playbackOnlineTtsUrl'),
        controller: _controller,
        keyboardType: TextInputType.url,
        autocorrect: false,
        onSubmitted: (_) => unawaited(_save()),
        decoration: const InputDecoration(
          labelText: 'Next.js 在线语音服务地址（可选）',
          hintText: 'https://your-lexiloop.example.com',
          helperText: '复用 /api/tts 接口；单词文本会发送到该服务。',
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: LexiSpace.s12),
      TextField(
        key: const Key('playbackOnlineTtsPassword'),
        controller: _password,
        obscureText: _obscurePassword,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Next.js 登录密码',
          helperText: '保存在设备安全存储中；留空表示不修改已保存密码。',
          helperMaxLines: 2,
          suffixIcon: IconButton(
            tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
            icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => unawaited(_save()),
          child: const Text('保存地址和密码'),
        ),
      ),
    ],
  );
}

/// 发音来源分组：来源、失败降级、测试以及 Android 语音服务入口。
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
        title: '发音方式',
        subtitle: '可使用系统语音、词典录音或无需自建服务器的 Edge TTS。在线方式会把待朗读文本发送给对应服务。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<SpeechSource>(
              key: const Key('playbackSpeechSource'),
              initialValue: playback.speechSource,
              decoration: const InputDecoration(labelText: '发音来源'),
              items: <DropdownMenuItem<SpeechSource>>[
                for (final source in SpeechSource.values)
                  DropdownMenuItem(value: source, child: Text(source.label)),
              ],
              onChanged: (source) {
                if (source == null) return;
                unawaited(
                  saveSettings(ref, <String, Object?>{
                    'speechSource': source.wire,
                  }),
                );
              },
            ),
            const SizedBox(height: LexiSpace.s12),
            if (playback.speechSource == SpeechSource.online)
              _OnlineTtsAddressField(value: playback.onlineTtsBaseUrl),
            SettingsSwitchRow(
              label: '失败时自动尝试备用方式',
              description: '系统缺少英文语音包时可改用 Edge TTS 或在线词典；离线时仍能正常学习。',
              value: playback.speechFallbackEnabled,
              onChanged: (value) => saveSettings(ref, <String, Object?>{
                'speechFallbackEnabled': value,
              }),
            ),
            Wrap(
              spacing: LexiSpace.s8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => unawaited(_testSpeech(context, ref)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('试听发音'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(openSystemSpeechSettings(context)),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('系统语音设置'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_diagnoseEdge(context, ref)),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('Edge 诊断'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: LexiSpace.s12),
      SettingsSectionCard(
        title: '真人录音',
        subtitle: '词典站点提供的是真人朗读 MP3，音质明显好于系统合成音；首次获取需要联网。',
        child: SettingsSwitchRow(
          switchKey: const Key('playbackHumanAudio'),
          label: '优先使用词典真人发音',
          description:
              '在「自动选择」模式开启时，词典录音失效会自动回落系统朗读；关闭后只用系统朗读，完全不联网（手动选 Edge TTS 除外）。',
          value: playback.humanAudioEnabled,
          onChanged: (value) =>
              saveSettings(ref, <String, Object?>{'humanAudioEnabled': value}),
        ),
      ),
    ],
  );

  Future<void> _diagnoseEdge(BuildContext context, WidgetRef ref) async {
    final lines = await _collectEdgeDiagnostics(ref);
    if (!context.mounted) return;
    await _showEdgeDiagnostics(context, lines.join('\n'));
  }

  Future<List<String>> _collectEdgeDiagnostics(WidgetRef ref) async {
    final lines = <String>['Edge TTS 诊断 · hello'];
    final playback = (await ref.read(settingsServiceProvider).load()).playback;
    try {
      lines.add('1. 正在连接 Edge 并合成 MP3…');
      final bytes = await DirectEdgeSpeech().diagnose(
        text: 'hello',
        accent: playback.defaultAccent,
      );
      lines.add('2. 合成成功：${bytes.length} 字节');
      try {
        final player = ref.read(audioPlayerPortProvider);
        await player.prepare(bytes, speed: 1);
        lines.add('3. Android 音频解码成功');
        await player.play();
        lines.add('4. 播放调用成功（请确认扬声器有声音）');
      } on Object catch (error) {
        lines.add('3. 播放失败：${error.runtimeType}: $error');
      }
    } on Object catch (error) {
      lines.add('2. 连接/合成失败：${error.runtimeType}: $error');
    }
    return lines;
  }

  Future<void> _showEdgeDiagnostics(BuildContext context, String report) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edge TTS 诊断结果'),
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

  Future<void> _testSpeech(BuildContext context, WidgetRef ref) async {
    // 不使用构建时的 playback 快照：用户刚切换来源后，必须试听已落库的设置。
    final latest = await ref.read(settingsServiceProvider).load();
    if (!context.mounted) return;
    final selected = latest.playback;
    final speaker = ref.read(wordSpeakerProvider)
      ..humanAudioEnabled = selected.humanAudioEnabled;
    final result = await speaker.speak(
      SpeechRequest(
        term: 'hello',
        accent: selected.defaultAccent,
        playback: selected,
      ),
    );
    if (!context.mounted) return;
    final message = switch (result) {
      HumanRecordingPlayed() => '试听成功：词典录音',
      OnlineVoicePlayed() => '试听成功：Next.js 在线 TTS',
      DirectEdgeVoicePlayed() => '试听成功：Edge TTS 直连',
      SystemVoicePlayed() => '试听成功：系统朗读',
      SpeechDisabled() => '当前已关闭发音，请先选择其他发音方式',
      SpeechFailed(:final error) => '试听失败：${error.message}。可切换发音方式或安装系统语音包。',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
