/// 音频播放器的抽象。
///
/// **为什么要有这个接口**：`just_audio` 是平台通道插件，构造它就意味着
/// 依赖平台侧实现，单元测试进程里不可用。把「把一段音频放出来」抽成接口后，
/// 真人录音优先、系统朗读兜底这条**策略**可以完全脱离插件验证——
/// 与 `lib/services/tts_service.dart` 的 `SpeechEngine` 同一套做法。
library;

import 'dart:typed_data';

/// 音频播放器的抽象。
abstract interface class AudioPlayerPort {
  /// 装载待播放的音频字节。
  ///
  /// 传入**已经下载好的字节**而不是 URL，是为了让缓存能决定命中与否：
  /// 命中时播放根本不应该再发出网络请求。
  /// 装载失败必须抛出，由上层决定是否回落到系统朗读。
  ///
  /// [speed] 是**倍率**（1 = 原速），在装载时就定下来：真人录音的语速与
  /// 系统朗读共用设置页那一套倍率，两者必须落在同一刻度上，否则同一个词
  /// 走录音和走朗读会听到两种速度。播放器可以自己改变速（`just_audio` 的
  /// `setSpeed`），不必重新下载。
  Future<void> prepare(Uint8List audio, {required double speed});

  /// 播放当前装载的音频。
  Future<void> play();

  /// 停止播放。
  Future<void> stop();

  /// 释放播放器占用的平台资源。
  Future<void> dispose();
}
