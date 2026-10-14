/// 平台能力差异的集中封装。
///
/// **为什么需要它**：双端并非完全对等。最典型的是 TTS——
/// `flutter_tts` 的 `synthesizeToFile` 只在 Android 与 iOS 可用，
/// **macOS 不支持**。若把这判断散落在语音服务里，会重蹈旧版
/// `REVIEW.md` 点名的「同一逻辑多处实现」覆辙。
///
/// 所有平台分支必须经由本模块，`lib/` 其余位置不得直接 import `dart:io`
/// 判断 `Platform.isMacOS`。
library;

import 'dart:io' show Platform;

/// 当前运行平台的能力集。
///
/// 用抽象基类而非裸布尔值，便于测试注入替代实现。
abstract final class PlatformCaps {
  /// 是否为桌面端（macOS）。
  static bool get isDesktop => Platform.isMacOS;

  /// 是否为移动端（Android）。
  static bool get isMobile => Platform.isAndroid;

  /// 系统 TTS 是否支持把合成结果落盘缓存。
  ///
  /// Android 支持 `synthesizeToFile`；macOS 不支持，只能实时朗读。
  /// 影响：Android 可预生成音频文件加速重复播放，macOS 直接朗读。
  static bool get supportsTtsFileSynthesis => Platform.isAndroid;

  /// 是否需要引导用户安装系统语音包。
  ///
  /// Android 的 TTS 依赖 Google TTS 引擎与已下载的语言数据，
  /// 缺失时朗读会静默无声，必须显式检测并引导。
  /// macOS 系统自带语音，无需引导。
  static bool get requiresVoicePackSetup => Platform.isAndroid;

  /// 系统 TTS 的语速取值范围下限。
  ///
  /// Android 的 `setSpeechRate` 语义是倍率区间 0.0–2.0，
  /// 与旧版 Web 的 `playbackRate` 不完全一致，双端都需实测校准。
  static const double minSpeechRate = 0;

  /// 系统 TTS 的语速取值范围上限。
  static const double maxSpeechRate = 2;

  /// 是否需要对全屏高斯模糊做性能降级。
  ///
  /// 旧版 `globals.css` 的环境光背景是 4 层 `blur(80px)` 径向渐变，
  /// 在中低端 Android 上会掉到 40fps 以下。桌面端 GPU 充足，无需降级。
  static bool get needsBlurDowngrade => Platform.isAndroid;
}
