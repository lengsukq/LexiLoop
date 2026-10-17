/// 音频层测试共用的假实现。
///
/// **为什么不用 mocktail 生成**：`AudioPlayerPort` / `AudioDownloadPort` /
/// `SpeechEngine` 都很小，手写假件反而更清楚——尤其是下载器需要记录
/// 并发峰值与在途门闩，这些用 mock 的 `thenAnswer` 写起来更绕。
library;

import 'dart:async';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:lexiloop/services/audio/audio_downloader.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';
import 'package:lexiloop/services/tts_service.dart';

/// 记录调用轨迹的假播放器。
class FakeAudioPlayer implements AudioPlayerPort {
  /// 每次 `prepare` 收到的字节。
  final List<Uint8List> prepared = <Uint8List>[];

  /// 每次 `prepare` 收到的语速倍率，与 [prepared] 一一对应。
  final List<double> preparedSpeeds = <double>[];

  /// `play` 的调用次数。
  int playCount = 0;

  /// `stop` 的调用次数。
  int stopCount = 0;

  /// `dispose` 的调用次数。
  int disposeCount = 0;

  /// `prepare` 时抛出的异常；为 `null` 表示不抛。
  Exception? prepareError;

  /// `play` 时抛出的异常；为 `null` 表示不抛。
  Exception? playError;

  @override
  Future<void> prepare(Uint8List audio, {required double speed}) async {
    final error = prepareError;
    if (error != null) throw error;
    prepared.add(audio);
    preparedSpeeds.add(speed);
  }

  @override
  Future<void> play() async {
    final error = playError;
    if (error != null) throw error;
    playCount += 1;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

/// 记录调用轨迹、并可精确控制并发的假下载器。
class FakeAudioDownloader implements AudioDownloadPort {
  /// 每次 `download` 的地址，按调用顺序。
  final List<Uri> downloaded = <Uri>[];

  /// 需要失败的地址集合（以字符串形式匹配）。
  final Set<String> failing = <String>{};

  /// 地址到字节的映射；未登记的地址返回一段占位字节。
  final Map<String, Uint8List> payloads = <String, Uint8List>{};

  /// 当前在途下载数。
  int get active => _active;

  /// 观测到的并发峰值。
  int get peakConcurrency => _peak;

  final Completer<void> _gate = Completer<void>();
  int _active = 0;
  int _peak = 0;

  /// 放行所有被门闩挡住的下载。
  void openGate() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Uint8List> download(Uri url) async {
    final key = url.toString();
    downloaded.add(url);
    _active += 1;
    _peak = max(_peak, _active);
    try {
      await _gate.future;
      if (failing.contains(key)) {
        throw StateError('模拟下载失败：$key');
      }
      return payloads[key] ?? Uint8List.fromList(<int>[1, 2, 3]);
    } finally {
      _active -= 1;
    }
  }
}

/// 记录调用轨迹的假语音引擎。
class RecordingSpeechEngine implements SpeechEngine {
  /// 每次 `configure` 的参数（语速, 语言）。
  final List<(double, String)> configureCalls = <(double, String)>[];

  /// 每次 `speak` 的文本。
  final List<String> spoken = <String>[];

  /// `isLanguageAvailable` 的返回值。
  bool languageAvailable = true;

  /// `speak` 时抛出的异常；为 `null` 表示不抛。
  Exception? speakError;

  @override
  Future<void> configure({
    required double rate,
    required String language,
  }) async {
    configureCalls.add((rate, language));
  }

  @override
  Future<void> speak(String text) async {
    final error = speakError;
    if (error != null) throw error;
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => languageAvailable;
}

/// 让挂起的 `await` 逐层推进若干轮。
///
/// 用于「断言并发峰值」这类需要在挂起状态下观察的测试。
Future<void> settle(int rounds) async {
  for (var round = 0; round < rounds; round += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
