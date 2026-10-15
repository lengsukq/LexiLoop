/// 平台能力差异的集中封装。
///
/// **为什么需要它**：多端并非完全对等。最典型的是 TTS——
/// `flutter_tts` 的 `synthesizeToFile` 只在 Android 与 iOS 可用，
/// **macOS 不支持**；Web 上既没有文件合成，也没有「语音包」这个概念。
/// 若把这判断散落在语音服务里，会重蹈旧版 `REVIEW.md` 点名的
/// 「同一逻辑多处实现」覆辙。
///
/// **为什么不再 import `dart:io`**：`Platform.isMacOS` / `Platform.isAndroid`
/// 在浏览器里既编译不过也没有意义。改用 `kIsWeb` + `defaultTargetPlatform`
/// （来自 `package:flutter/foundation.dart`），一套判断同时覆盖原生与 Web；
/// `lib/` 其余位置不得再出现 `dart:io`。
library;

import 'package:flutter/foundation.dart';

/// 平台能力矩阵：由「是否浏览器」与「目标平台」推导出的全部平台差异。
///
/// **为什么把它与 [PlatformCaps] 分开**：`kIsWeb` 是编译期常量，在
/// `flutter test` 的 VM 进程里恒为 `false`，Web 那一行构造不出来；而
/// `defaultTargetPlatform` 在测试进程里被 Flutter 强制成 `android`
/// （`_platform_io.dart` 的 `FLUTTER_TEST` 分支），宿主机是 macOS 这件事
/// 同样测不到。抽成可构造的值对象后，`test/core/platform_test.dart` 才能把
/// Web / macOS / Android 三行逐一穷举，[PlatformCaps] 只负责接线。
final class PlatformProfile {
  /// 以「是否浏览器 + 目标平台」构造。
  const new({required this.isWeb, required this.targetPlatform});

  /// 是否运行在浏览器里。
  final bool isWeb;

  /// Flutter 认定的目标平台。Web 上它没有意义，一切由 [isWeb] 决定。
  final TargetPlatform targetPlatform;

  /// 是否为桌面端（macOS）。
  bool get isDesktop => !isWeb && targetPlatform == TargetPlatform.macOS;

  /// 是否为移动端（Android）。
  bool get isMobile => !isWeb && targetPlatform == TargetPlatform.android;

  /// 系统 TTS 是否支持把合成结果落盘缓存。
  bool get supportsTtsFileSynthesis => isMobile;

  /// 是否需要引导用户安装系统语音包。
  bool get requiresVoicePackSetup => isMobile;

  /// 是否需要对全屏高斯模糊做性能降级。
  bool get needsBlurDowngrade => isMobile;
}

/// 当前运行平台的能力集。
///
/// 用抽象基类而非裸布尔值，便于测试注入替代实现。
abstract final class PlatformCaps {
  /// 当前平台的画像。
  ///
  /// 每次读取都重新求值，而不是缓存成 `static final`：测试会用
  /// `debugDefaultTargetPlatformOverride` 逐行切换平台，缓存会把这个能力废掉。
  static PlatformProfile get profile =>
      PlatformProfile(isWeb: kIsWeb, targetPlatform: defaultTargetPlatform);

  /// 是否运行在浏览器里。
  ///
  /// Web 既不算桌面端也不算移动端，因此 [isDesktop] 与 [isMobile] 同时为
  /// `false`。需要「三选一」语义的调用方必须先看这个值。
  static bool get isWeb => profile.isWeb;

  /// 是否为桌面端（macOS）。
  static bool get isDesktop => profile.isDesktop;

  /// 是否为移动端（Android）。
  static bool get isMobile => profile.isMobile;

  /// 系统 TTS 是否支持把合成结果落盘缓存。
  ///
  /// Android 支持 `synthesizeToFile`；macOS 不支持，只能实时朗读。
  /// 浏览器的 SpeechSynthesis 同样只支持实时朗读。
  /// 影响：Android 可预生成音频文件加速重复播放，其余端直接朗读。
  static bool get supportsTtsFileSynthesis => profile.supportsTtsFileSynthesis;

  /// 是否需要引导用户安装系统语音包。
  ///
  /// Android 的 TTS 依赖 Google TTS 引擎与已下载的语言数据，
  /// 缺失时朗读会静默无声，必须显式检测并引导。
  /// macOS 系统自带语音；浏览器上语音由操作系统与浏览器共同决定，
  /// 没有可供应用引导的安装入口，因此不需要这一步。
  static bool get requiresVoicePackSetup => profile.requiresVoicePackSetup;

  /// 系统 TTS 的语速取值范围下限。
  ///
  /// Android 的 `setSpeechRate` 语义是倍率区间 0.0–2.0，
  /// 与旧版 Web 的 `playbackRate` 不完全一致，各端都需实测校准。
  static const double minSpeechRate = 0;

  /// 系统 TTS 的语速取值范围上限。
  static const double maxSpeechRate = 2;

  /// 是否需要对全屏高斯模糊做性能降级。
  ///
  /// 旧版 `globals.css` 的环境光背景是 4 层 `blur(80px)` 径向渐变，
  /// 在中低端 Android 上会掉到 40fps 以下。桌面端 GPU 充足，无需降级。
  ///
  /// Web 不降级：浏览器把模糊交给合成层，桌面浏览器普遍够用，
  /// 而降级会立刻让 Web 的观感偏离设计稿。低端设备上的取舍见
  /// `docs/FLUTTER_WEB.md`。
  static bool get needsBlurDowngrade => profile.needsBlurDowngrade;
}
