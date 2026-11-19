/// 发音结果。
///
/// **为什么用 sealed 而不是布尔字段**：「真人录音」「系统朗读」「都没响」
/// 三种结果对界面层的含义完全不同（是否要提示「已回落到系统朗读」、
/// 是否要提示失败），用两个互相组合的布尔量迟早会出现 `played == false`
/// 且 `fellBack == true` 这种自相矛盾的组合。`sealed` 让 `switch` 的
/// 穷尽性由编译器保证，新增一种结果时所有调用点都会编译失败。
library;

import 'package:lexiloop/core/errors.dart';

/// 一次发音的结果。
sealed class SpeechResult {
  /// 以子类型自身构造。
  const new();

  /// 是否真的发出了声音。
  bool get played => true;

  /// 是否因为拿不到真人录音而改用了系统朗读。
  ///
  /// 界面层据此提示「已回落到系统朗读」——真人录音听起来明显更好，
  /// 静默降级会让用户以为词典音频坏了。
  bool get fellBackToSystemVoice => false;
}

/// Flutter 客户端直接通过 Edge WebSocket 合成、播放成功。
final class DirectEdgeVoicePlayed extends SpeechResult {
  /// 无需 Next.js 参与的语音合成结果。
  const new();
}

/// 通过用户配置的 Next.js Edge TTS 返回的 MP3 播放成功。
final class OnlineVoicePlayed extends SpeechResult {
  /// 在线合成并播放成功。
  const new();
}

/// 用户在设置中明确关闭发音，不属于错误。
final class SpeechDisabled extends SpeechResult {
  /// 不需要音频的结果。
  const new();

  @override
  bool get played => false;
}

/// 播放的是词典提供的真人录音。
final class HumanRecordingPlayed extends SpeechResult {
  /// 以固定值构造。
  const new();
}

/// 没有真人录音，改用系统朗读。
final class SystemVoicePlayed extends SpeechResult {
  /// 以固定值构造。
  const new();

  @override
  bool get fellBackToSystemVoice => true;
}

/// 真人录音与系统朗读都没能发声。
final class SpeechFailed extends SpeechResult {
  /// 以归一化后的错误构造。
  const new(this.error);

  /// 失败原因，供日志与界面提示取文案。
  final AppError error;

  @override
  bool get played => false;
}
