/// 小游戏里的词条朗读。
///
/// 旧版 `games/page.tsx` 用 `playCachedTts(term, "US")`：进入听音辨词 /
/// 词义冲刺的每一题后延迟 `gameAutoSpeakDelayMs` 自动播一次，听音辨词另有
/// 可重复点击的喇叭按钮，点任一选项也会把该词条读一遍。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';

/// 朗读一个小游戏词条。
///
/// **为什么做成可注入的函数而不是直接调服务**：朗读是副作用，界面不该在
/// widget 测试里真的去开播放器；换成 provider 之后测试可以覆盖成一个只记录
/// 调用次数的假实现，从而断言「每题只自动播一次」。
typedef GameSpeaker = Future<SpeechResult> Function(String term);

/// 小游戏朗读服务。
///
/// **为什么走 `WordSpeaker` 而不是 `TtsService`**：`WordSpeaker.speak` 把
/// 「真人录音 → 系统朗读」的降级吸收在内部并且**永不抛异常**，界面不需要
/// 用空 `catch` 吞掉朗读失败；换成 `ttsServiceProvider.speakTerm` 只需要改
/// [speakGameTerm] 一个函数。
///
/// **当前实际听感**：游戏题目不带发音列表（`SpeechRequest.pronunciations`
/// 为空），所以 `resolveHumanAudioUrl` 会直接回落到系统朗读——与旧版
/// `playCachedTts` 在缓存未命中时的行为一致。等题目带上发音列表后，
/// 这里不用改一行就会自动优先播真人录音。
final Provider<GameSpeaker> gameSpeakerProvider = Provider<GameSpeaker>(
  (ref) =>
      (term) => speakGameTerm(ref, term),
);

/// 朗读一个词条（美音）。
///
/// 旧版固定传 `"US"`，与 [PlaybackSettings.defaultAccent] 无关，
/// 因此这里也写死美音。
Future<SpeechResult> speakGameTerm(Ref ref, String term) {
  final playback =
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;
  return ref
      .read(wordSpeakerProvider)
      .speak(SpeechRequest(term: term, accent: Accent.us, playback: playback));
}
