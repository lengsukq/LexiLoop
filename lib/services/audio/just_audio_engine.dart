/// 基于 `just_audio` 的播放器实现。
///
/// **为什么用内存字节而不是 `setUrl`**：`just_audio` 的 `setUrl` 会自己发
/// HTTP 请求，这样一来缓存命中与否就完全不在我们手里——同一个词第二次点
/// 播放仍会重新下载。改成「`AudioCache` 决定字节、`AudioPlayerPort` 只负责
/// 放声音」之后，命中缓存时零网络请求这条性质由类型系统保证。
///
/// **为什么整文件豁免 `experimental_member_use`**：`StreamAudioSource` 与
/// `StreamAudioResponse` 是 `just_audio` 目前唯一能把「已下载的字节」交给
/// 播放器的官方接口（另一条路是写临时文件再 `setFilePath`，多一次落盘与
/// 一整套临时文件生命周期管理）。为两处构造各写一行豁免不如在文件头说明
/// 一次；升级 `just_audio` 时本文件是唯一的观察点。
// ignore_for_file: experimental_member_use
library;

import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:lexiloop/services/audio/audio_constants.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';

/// 基于 `just_audio` 的 `AudioPlayerPort` 实现。
final class JustAudioEngine implements AudioPlayerPort {
  /// 以可选的播放器实例构造。
  new({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  /// 装载音频字节。
  ///
  /// 失败时按 `just_audio` 的契约直接上抛，由 `WordSpeaker` 判断是否回落——
  /// 播放器层没有发言权，它不知道「没有真人录音」是正常情况还是缺陷。
  @override
  Future<void> prepare(Uint8List audio) =>
      _player.setAudioSource(_InMemoryAudioSource(audio)).then((_) {});

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 把整段字节喂给播放器的数据源。
///
/// 声明 `rangeRequestsSupported: false` 并始终返回完整缓冲区：`just_audio`
/// 允许数据源无视区间请求，只要如实说明自己不支持即可。它请求的是
/// 已经完整下载到内存的十几 KB mp3，切分区间反而多一层出错面。
final class _InMemoryAudioSource extends StreamAudioSource {
  /// 以音频字节构造。
  new(this._audio);

  final Uint8List _audio;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: _audio.lengthInBytes,
      contentLength: _audio.lengthInBytes,
      offset: 0,
      contentType: audioContentType,
      stream: Stream<List<int>>.value(_audio),
    );
  }
}
