/// 发音结果。
///
/// **为什么用 sealed 而不是布尔字段**：有道真人录音、Edge 神经语音、系统朗读、
/// 静音与失败对界面层的含义各不相同；`sealed` 让 `switch` 的穷尽性由编译器保证，
/// 并且通过 [SpeechResult.fellBackFrom] 精确记录「本来该走哪个首选引擎，因失败而顺延到了当前引擎」。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 一次发音的结果。
sealed class SpeechResult {
  /// 以子类型自身构造。
  const new();

  /// 是否真的发出了声音。
  bool get played => true;

  /// 实际完成播报的引擎；未播报时为 `null`。
  SpeechSource? get playedSource => null;

  /// 若因排在前面的适用引擎失败而顺延到当前引擎，记录首个失败引擎；否则为 `null`。
  SpeechSource? get fellBackFrom => null;

  /// 是否发生了从首选到备用引擎的自动回退。
  bool get fellBack => fellBackFrom != null;

  /// 是否因前面的引擎不可用而回落到了系统朗读。
  bool get fellBackToSystemVoice =>
      fellBack && playedSource == SpeechSource.system;
}

/// 播放的是有道或词典提供的真人录音。
final class HumanRecordingPlayed extends SpeechResult {
  /// 以可选的回退来源构造。
  const new({this.fellBackFrom});

  @override
  final SpeechSource? fellBackFrom;

  @override
  SpeechSource get playedSource => SpeechSource.youdao;
}

/// Flutter 客户端直接通过 Edge WebSocket 合成并播放成功。
final class DirectEdgeVoicePlayed extends SpeechResult {
  /// 以可选的回退来源构造。
  const new({this.fellBackFrom});

  @override
  final SpeechSource? fellBackFrom;

  @override
  SpeechSource get playedSource => SpeechSource.edge;
}

/// 通过设备系统 TTS 完成朗读。
final class SystemVoicePlayed extends SpeechResult {
  /// 以可选的回退来源构造。
  const new({this.fellBackFrom});

  @override
  final SpeechSource? fellBackFrom;

  @override
  SpeechSource get playedSource => SpeechSource.system;
}

/// 用户在设置中关闭了全部发音引擎，或本次请求已被更新的朗读打断；不属于错误。
final class SpeechDisabled extends SpeechResult {
  /// 不需要音频的结果。
  const new();

  @override
  bool get played => false;
}

/// 所有已启用的发音引擎都没能发声。
final class SpeechFailed extends SpeechResult {
  /// 以归一化后的错误构造。
  const new(this.error);

  /// 失败原因，供日志与界面提示取文案。
  final AppError error;

  @override
  bool get played => false;
}
