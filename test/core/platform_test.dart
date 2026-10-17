/// 平台能力判定的测试。
///
/// 钉住的是**能力矩阵的三行**：Web / macOS / Android。
///
/// **为什么测的是 `PlatformProfile` 而不是直接测 `PlatformCaps`**：
/// `kIsWeb` 是编译期常量，在 `flutter test` 的 VM 进程里恒为 `false`，
/// Web 那一行根本构造不出来；而 `defaultTargetPlatform` 在测试进程里被
/// Flutter 强制成 `android`（`_platform_io.dart` 里的 `FLUTTER_TEST` 分支），
/// 所以「宿主是 macOS」这件事也测不到。把判定抽成可构造的值对象后，
/// 三行都能逐一穷举，`PlatformCaps` 只负责接线。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';

void main() {
  tearDown(() {
    // 不清理会污染同文件内后续用例的平台判定。
    debugDefaultTargetPlatformOverride = null;
  });

  group('Web 行', () {
    test('无论底层目标平台是什么，六个能力全为 false', () {
      for (final platform in TargetPlatform.values) {
        final profile = PlatformProfile(isWeb: true, targetPlatform: platform);
        final reason = 'targetPlatform=$platform';

        expect(profile.isDesktop, isFalse, reason: reason);
        expect(profile.isMobile, isFalse, reason: reason);
        expect(profile.supportsTtsFileSynthesis, isFalse, reason: reason);
        expect(profile.requiresVoicePackSetup, isFalse, reason: reason);
        expect(profile.needsBlurDowngrade, isFalse, reason: reason);
        expect(profile.usesUtteranceRateScale, isFalse, reason: reason);
      }
    });
  });

  group('macOS 行', () {
    test('桌面端：非移动、不支持文件合成、不需要语音包、不降级模糊', () {
      const profile = PlatformProfile(
        isWeb: false,
        targetPlatform: TargetPlatform.macOS,
      );

      expect(profile.isDesktop, isTrue);
      expect(profile.isMobile, isFalse);
      expect(profile.supportsTtsFileSynthesis, isFalse);
      expect(profile.requiresVoicePackSetup, isFalse);
      expect(profile.needsBlurDowngrade, isFalse);
      // 语速按 AVSpeechUtterance.rate 解释：必须折算，否则默认设置即最快。
      expect(profile.usesUtteranceRateScale, isTrue);
    });
  });

  group('Android 行', () {
    test('移动端：支持文件合成、需要语音包、降级模糊', () {
      const profile = PlatformProfile(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );

      expect(profile.isDesktop, isFalse);
      expect(profile.isMobile, isTrue);
      expect(profile.supportsTtsFileSynthesis, isTrue);
      expect(profile.requiresVoicePackSetup, isTrue);
      expect(profile.needsBlurDowngrade, isTrue);
      // flutter_tts 在 Android 侧会把 Dart 值 ×2，Dart 的 1.0 已是正常语速。
      expect(profile.usesUtteranceRateScale, isFalse);
    });
  });

  group('朗读语速刻度', () {
    test('只有 iOS 与 macOS 走 AVSpeechUtterance 的刻度', () {
      for (final platform in TargetPlatform.values) {
        final profile = PlatformProfile(isWeb: false, targetPlatform: platform);
        final expected =
            platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

        expect(profile.usesUtteranceRateScale, expected, reason: '$platform');
      }
    });
  });

  group('互斥性', () {
    test('Web / 桌面 / 移动三态至多命中一个', () {
      for (final isWeb in <bool>[true, false]) {
        for (final platform in TargetPlatform.values) {
          final profile = PlatformProfile(
            isWeb: isWeb,
            targetPlatform: platform,
          );
          final hits = <String>[
            if (profile.isWeb) 'web',
            if (profile.isDesktop) 'desktop',
            if (profile.isMobile) 'mobile',
          ];

          expect(
            hits.length,
            lessThanOrEqualTo(1),
            reason: 'isWeb=$isWeb targetPlatform=$platform 同时命中 $hits',
          );
        }
      }
    });

    test('非 macOS / Android 的原生平台与 Web 一样「什么能力都没有」', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        final profile = PlatformProfile(isWeb: false, targetPlatform: platform);

        expect(profile.isDesktop, isFalse, reason: '$platform');
        expect(profile.isMobile, isFalse, reason: '$platform');
      }
    });
  });

  group('PlatformCaps 接线', () {
    test('isWeb 直接跟随 kIsWeb', () {
      expect(PlatformCaps.isWeb, kIsWeb);
      // VM 测试进程不是浏览器；这条断言同时说明了上面为什么测不到 Web 行。
      expect(PlatformCaps.isWeb, isFalse);
    });

    test('能力跟随 defaultTargetPlatform', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlatformCaps.isDesktop, isFalse);
      expect(PlatformCaps.isMobile, isTrue);
      expect(PlatformCaps.supportsTtsFileSynthesis, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlatformCaps.isDesktop, isTrue);
      expect(PlatformCaps.isMobile, isFalse);
      expect(PlatformCaps.supportsTtsFileSynthesis, isFalse);
      expect(PlatformCaps.requiresVoicePackSetup, isFalse);
      expect(PlatformCaps.needsBlurDowngrade, isFalse);
      expect(PlatformCaps.usesUtteranceRateScale, isTrue);
    });

    test('界面语速区间合法且包含默认语速', () {
      // 区间描述的是**倍率**，与平台无关；平台差异体现在下发前的折算上。
      expect(minSpeechRate, lessThan(maxSpeechRate));
      expect(minSpeechRate, 0.5);
      expect(maxSpeechRate, 2);
      expect(defaultSpeechRate, inInclusiveRange(minSpeechRate, maxSpeechRate));
    });

    test('折算系数区间与 AVSpeech 的可用区间一致', () {
      expect(minUtteranceRateFactor, lessThan(maxUtteranceRateFactor));
      expect(maxUtteranceRateFactor, 1);
      // 默认倍率折算后必须**不是**顶格，否则「默认即最快」会原样复发。
      expect(
        defaultSpeechRate * avSpeechUtteranceDefaultRate,
        lessThan(maxUtteranceRateFactor),
      );
    });
  });
}
