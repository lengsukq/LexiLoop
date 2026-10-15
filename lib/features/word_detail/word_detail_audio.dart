/// 词条详情与词库列表的发音入口。
///
/// **为什么统一走这里**：详情页头部、发音栏、例句行与列表卡片四处都要
/// 发音，每处各写一遍「读设置 → 组请求 → 处理结果」必然漂移——旧版就是
/// 这样，`tts-client.ts` 与详情页 hook 各有一套口音与降级判断。
///
/// **为什么用 `WordSpeaker` 而不是直接调 `TtsService`**：真人录音（词典
/// mp3）优先是相对旧版唯一不能丢的能力，`WordSpeaker` 把它与系统朗读的
/// 降级关系收敛在一个永不抛异常的服务里；界面只需要「调用 → 看结果」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';

/// 真人录音不可用时的提示文案。
const String humanAudioFallbackMessage = '真人录音不可用，已改用系统朗读。';

/// 朗读一段文本，并把失败或降级提示给用户。
///
/// [accent] 为空时用设置里的默认口音（`playback.defaultAccent`）：
/// 列表卡片与例句没有「按口音切换」的交互，让每个调用点各自解析默认值
/// 只会多出几份一模一样的兜底逻辑。
///
/// [pronunciations] 为空表示「没有真人录音可用」（如例句），此时直接走
/// 系统朗读，不会给出降级提示。
///
/// **真人录音开关的接线方式**：每次都把 `playback.humanAudioEnabled` 同步到
/// `speaker.humanAudioEnabled` 再调用。选这个方案而不是「在 provider 里读
/// 一次就固定」，是因为设置页改完开关不会重建 `wordSpeakerProvider`——
/// 只读一次的话用户关掉开关后必须重启应用才生效。
Future<void> speakWithWordSpeaker({
  required BuildContext context,
  required WidgetRef ref,
  required String term,
  Accent? accent,
  LexicalContentType contentType = LexicalContentType.word,
  List<PronunciationView> pronunciations = const <PronunciationView>[],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final playback =
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;
  final effectiveAccent = accent ?? playback.defaultAccent;
  final expectsHumanAudio =
      playback.humanAudioEnabled &&
      resolveHumanAudioUrl(
            term: term,
            accent: effectiveAccent,
            pronunciations: pronunciations,
          ) !=
          null;
  final speaker = ref.read(wordSpeakerProvider)
    ..humanAudioEnabled = playback.humanAudioEnabled;
  final result = await speaker.speak(
    SpeechRequest(
      term: term,
      accent: effectiveAccent,
      playback: playback,
      contentType: contentType,
      pronunciations: pronunciations,
    ),
  );
  final message = _messageOf(result, expectsHumanAudio: expectsHumanAudio);
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 结果对应的用户提示；无需提示时返回 `null`。
///
/// **只在「本来有真人录音却回落到系统朗读」时提示降级**：
/// `SpeechResult.fellBackToSystemVoice` 在「压根没有真人录音」时同样为真
/// （词典没给音频的词条遍地都是），无差别提示只会变成人人无视的噪音。
String? _messageOf(SpeechResult result, {required bool expectsHumanAudio}) {
  if (result is SpeechFailed) return result.error.message;
  if (expectsHumanAudio && result.fellBackToSystemVoice) {
    return humanAudioFallbackMessage;
  }
  return null;
}
