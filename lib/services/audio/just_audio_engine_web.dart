/// 浏览器直接用 data URI 播放已获得的音频字节，不依赖文件系统。
library;

import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';

/// 浏览器中的音频播放适配器。
final class JustAudioEngine implements AudioPlayerPort {
  /// 允许在测试中传入可控的播放器。
  new({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> prepare(Uint8List audio, {required double speed}) async {
    final uri = Uri.dataFromBytes(audio, mimeType: 'audio/mpeg');
    await _player.stop();
    await _player.setUrl(uri.toString());
    await _player.setSpeed(speed);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
