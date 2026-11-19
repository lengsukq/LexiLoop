/// Edge TTS 持久化音频缓存（Android/macOS/iOS）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

Future<File> _cacheFile(String key) async {
  final root = await getApplicationSupportDirectory();
  final folder = Directory('${root.path}/speech_cache/edge');
  await folder.create(recursive: true);
  final filename = sha256.convert(key.codeUnits).toString();
  return File('${folder.path}/$filename.mp3');
}

/// 获取已缓存的合成结果。
Future<Uint8List?> readCachedEdgeAudio(String key) async {
  final file = await _cacheFile(key);
  if (!file.existsSync()) return null;
  final bytes = await file.readAsBytes();
  return bytes.isEmpty ? null : bytes;
}

/// 将合成结果保存在本机应用目录。
Future<void> writeCachedEdgeAudio(String key, Uint8List bytes) async {
  final file = await _cacheFile(key);
  await file.writeAsBytes(bytes, flush: true);
}
