/// Android/iOS/macOS MP3 播放：使用临时文件避免内存 HTTP 代理兼容问题。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';
import 'package:path_provider/path_provider.dart';

/// 将已下载的 MP3 写到应用缓存目录，交给平台原生解码器播放。
final class JustAudioEngine implements AudioPlayerPort {
  /// 允许在测试中注入播放器。
  new({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  File? _currentFile;

  @override
  Future<void> prepare(Uint8List audio, {required double speed}) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/lexiloop_audio_${DateTime.now().microsecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(audio, flush: true);
    final previous = _currentFile;
    try {
      await _player.stop();
      await _player.setFilePath(file.path);
      await _player.setSpeed(speed);
      _currentFile = file;
      if (previous != null) await _deleteQuietly(previous);
    } on Object {
      await _deleteQuietly(file);
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() async {
    await _player.dispose();
    final file = _currentFile;
    _currentFile = null;
    if (file != null) await _deleteQuietly(file);
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // 系统可能已清理临时文件。
    }
  }
}
