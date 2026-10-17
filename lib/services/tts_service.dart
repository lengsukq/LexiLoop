/// 语音朗读。
///
/// **为什么要有 [SpeechEngine] 抽象**：`flutter_tts` 是平台通道插件，
/// 在单元测试里不可用。把引擎抽成接口后，朗读的**调度逻辑**
/// （选口音、选语速、并发去重、失败降级）可以脱离插件测试，
/// 也便于将来换实现。
///
/// **双端差异**：Android 支持 `synthesizeToFile` 落盘缓存，macOS 不支持。
/// 该差异由 `core/platform.dart` 的 `PlatformCaps` 统一表达，
/// 本文件只消费它，不自己判断平台。
library;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 语言代码到 TTS 语言标识的映射。
///
/// TTS 引擎要的是 BCP-47（`en-US`），而词条里存的是 ISO 639-1（`en`）。
const Map<String, String> _ttsLanguageByCode = <String, String>{
  'en': 'en-US',
  'zh': 'zh-CN',
  'ja': 'ja-JP',
  'ko': 'ko-KR',
  'fr': 'fr-FR',
  'de': 'de-DE',
  'es': 'es-ES',
  'it': 'it-IT',
  'pt': 'pt-PT',
  'ru': 'ru-RU',
  'nl': 'nl-NL',
  'sv': 'sv-SE',
  'da': 'da-DK',
  'no': 'nb-NO',
};

/// 语音引擎的抽象。
abstract interface class SpeechEngine {
  /// 设置语速（倍率）与语言。
  Future<void> configure({required double rate, required String language});

  /// 朗读一段文本。
  Future<void> speak(String text);

  /// 停止当前朗读。
  Future<void> stop();

  /// 语言是否可用（Android 缺语音包时返回 false）。
  Future<bool> isLanguageAvailable(String language);
}

/// 基于 `flutter_tts` 的引擎实现。
class FlutterTtsEngine implements SpeechEngine {
  /// 以可选的插件实例构造（测试可注入假实现）。
  new({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;

  @override
  Future<void> configure({
    required double rate,
    required String language,
  }) async {
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configured = true;
  }

  @override
  Future<void> speak(String text) async {
    if (!_configured) {
      throw const PlatformCapabilityError(AppErrorCode.ttsUnavailable);
    }
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<bool> isLanguageAvailable(String language) async {
    final available = await _tts.isLanguageAvailable(language);
    return available == true;
  }
}

/// 朗读服务。
///
/// **职责边界**：只负责「把一段文本按当前设置读出来」。
/// 不负责音频缓存——Android 的 `synthesizeToFile` 缓存需要落盘路径与失效策略，
/// 属于后续独立能力；[PlatformCaps.supportsTtsFileSynthesis] 先把差异标出来。
class TtsService {
  /// 以引擎构造。
  new(this._engine);

  final SpeechEngine _engine;

  /// 当前已配置的语速；`null` 表示尚未配置。
  ///
  /// 存的是**界面倍率**而不是下发给引擎的参数：两个值只是同一份配置的两种
  /// 表示，去重比较用哪一个都行，但存倍率能让「换算」只有一个出口——
  /// 存引擎参数的话，读回来判断平台是否需要换算会多一层反推。
  double? _configuredRate;

  /// 当前已配置的语言；`null` 表示尚未配置。
  String? _configuredLanguage;

  /// 朗读一个词条。
  ///
  /// 语速按内容类型区分：句子比单词慢，否则长句会听不清。
  Future<void> speakTerm({
    required String term,
    required String sourceLanguage,
    required LexicalContentType contentType,
    required PlaybackSettings playback,
  }) async {
    final text = term.trim();
    if (text.isEmpty) return;
    await speak(
      text,
      languageCode: sourceLanguage,
      rate: playback.speedFor(contentType),
    );
  }

  /// 朗读任意文本。
  Future<void> speak(
    String text, {
    required String languageCode,
    required double rate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final language = _resolveLanguage(languageCode);
    final boundedRate = _boundedRate(rate);

    if (_configuredRate != boundedRate || _configuredLanguage != language) {
      await _engine.configure(
        rate: _engineRate(boundedRate),
        language: language,
      );
      _configuredRate = boundedRate;
      _configuredLanguage = language;
    }

    if (PlatformCaps.requiresVoicePackSetup &&
        !await _engine.isLanguageAvailable(language)) {
      throw const PlatformCapabilityError(AppErrorCode.ttsUnavailable);
    }

    try {
      await _engine.speak(trimmed);
    } on Object catch (error) {
      throw ExternalServiceError(
        AppErrorCode.ttsSynthesisFailed,
        details: error,
      );
    }
  }

  /// 停止朗读（离开页面时调用）。
  Future<void> stop() => _engine.stop();

  /// 把 ISO 639-1 代码映射为 BCP-47；未知语言原样返回，交给引擎判断。
  String _resolveLanguage(String code) =>
      _ttsLanguageByCode[code.toLowerCase()] ?? code;

  /// 语速夹到平台可接受区间。
  ///
  /// 夹的是**倍率**：设置页允许 [minSpeechRate]–[maxSpeechRate]，超出即视为
  /// 脏数据。换算到引擎刻度后仍可能越界（Apple 的可用区间比界面区间窄），
  /// 那一步由 [_engineRate] 的系数负责。
  double _boundedRate(double rate) => rate.clamp(minSpeechRate, maxSpeechRate);

  /// 把界面**倍率**折算成引擎认识的参数。
  ///
  /// Android 与 Web 的 `setSpeechRate` 都是倍率语义：Android 侧
  /// `flutter_tts` 会自己把 Dart 值 ×2 再交给 `TextToSpeech.setSpeechRate`，
  /// Web 侧 `SpeechSynthesisUtterance.rate` 直接就吃倍率，原样下发即可。
  ///
  /// iOS/macOS 不是：Dart 值被原样赋给 `AVSpeechUtterance.rate`，而那个刻度
  /// 以 [avSpeechUtteranceDefaultRate]（0.5）为正常语速、1.0 为上限。
  /// 若原样下发，界面默认的 1.0 就已经是引擎上限——这正是「默认设置下朗读
  /// 快得像赶场、把滑条往上拉还没变化」的根因。这里折算出 `0.5 × 倍率`，
  /// 让界面的 1.0 恰好等于引擎的正常语速。
  ///
  /// 再夹一次系数：`0.5 × 2.0` 正好顶格，界面倍率更大也不会越界，而
  /// AVSpeech 对越界值只会静默钳住——不夹的话「设置值 ≠ 实际值」会变成
  /// 一条无人察觉的偏差。
  double _engineRate(double multiplier) {
    if (!PlatformCaps.usesUtteranceRateScale) return multiplier;
    final scaled = multiplier * avSpeechUtteranceDefaultRate;
    return scaled.clamp(minUtteranceRateFactor, maxUtteranceRateFactor);
  }
}
