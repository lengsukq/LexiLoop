/// 原生端（Android / iOS / macOS）离线语音持久化缓存实现。
///
/// 目录布局：`<ApplicationSupport>/speech_cache/{youdao,edge}/{sha256(key)}.mp3`。
/// 沿用此前 Edge 缓存路径 `speech_cache/edge/`，保证升级后老缓存无缝复用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';
import 'package:path_provider/path_provider.dart';

const String _cacheRootFolder = 'speech_cache';
const String _mp3Extension = '.mp3';
const String _tmpExtension = '.tmp';

/// 创建原生平台磁盘缓存实例。
///
/// `flutter test` 进程默认不触碰宿主机应用支持目录（避免污染本机磁盘与平台通道
/// 跨 Zone 挂起）；需要验证真实磁盘行为的测试直接构造 [NativeSpeechDiskCache]
/// 并注入临时目录，或覆写 `speechDiskCacheProvider`。
SpeechDiskCachePort createPlatformDiskCache() =>
    Platform.environment.containsKey('FLUTTER_TEST')
    ? const _NoopTestDiskCache()
    : NativeSpeechDiskCache();

/// 基于本机文件系统的离线语音缓存。
class NativeSpeechDiskCache implements SpeechDiskCachePort {
  /// [rootDirectoryProvider] 仅供单元测试注入临时目录；生产环境自动使用应用支持目录。
  new({Future<Directory> Function()? rootDirectoryProvider})
    : _rootDirectoryProvider =
          rootDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _rootDirectoryProvider;
  Directory? _cachedRoot;

  @override
  bool get isSupported => true;

  @override
  Future<Uint8List?> read(SpeechCacheBucket bucket, String key) async {
    try {
      final file = await _audioFile(bucket, key, createDir: false);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      unawaited(_touchQuietly(file));
      return bytes;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(
    SpeechCacheBucket bucket,
    String key,
    Uint8List bytes,
  ) async {
    if (bytes.isEmpty) return;
    try {
      final target = await _audioFile(bucket, key, createDir: true);
      final temp = File('${target.path}$_tmpExtension');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } on Object {
      // 写磁盘失败（空间不足或权限受限）不应影响当前内存播报。
    }
  }

  @override
  Future<bool> contains(SpeechCacheBucket bucket, String key) async {
    try {
      final file = await _audioFile(bucket, key, createDir: false);
      return file.existsSync() && file.lengthSync() > 0;
    } on Object {
      return false;
    }
  }

  @override
  Future<SpeechCacheStats> stats() async {
    final youdao = await _bucketStats(SpeechCacheBucket.youdao);
    final edge = await _bucketStats(SpeechCacheBucket.edge);
    return SpeechCacheStats(
      youdaoFiles: youdao.files,
      youdaoBytes: youdao.bytes,
      edgeFiles: edge.files,
      edgeBytes: edge.bytes,
    );
  }

  @override
  Future<void> clear({SpeechCacheBucket? bucket}) async {
    final targets = bucket == null
        ? SpeechCacheBucket.values
        : <SpeechCacheBucket>[bucket];
    for (final target in targets) {
      await _clearBucket(target);
    }
  }

  @override
  Future<int> enforceLimit(int maxBytes) async {
    if (maxBytes <= 0) return 0;
    final entries = await _collectAllAudioEntries();
    var totalBytes = 0;
    for (final entry in entries) {
      totalBytes += entry.size;
    }
    if (totalBytes <= maxBytes) return 0;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    final targetBytes = (maxBytes * audioCacheEvictTargetRatio).floor();
    var removed = 0;
    for (final entry in entries) {
      if (totalBytes <= targetBytes) break;
      if (_deleteQuietly(entry.file)) {
        totalBytes -= entry.size;
        removed += 1;
      }
    }
    return removed;
  }

  Future<Directory> _bucketDir(
    SpeechCacheBucket bucket, {
    required bool createDir,
  }) async {
    final root = _cachedRoot ??= await _rootDirectoryProvider();
    final folder = Directory('${root.path}/$_cacheRootFolder/${bucket.folder}');
    if (createDir && !folder.existsSync()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<File> _audioFile(
    SpeechCacheBucket bucket,
    String key, {
    required bool createDir,
  }) async {
    final folder = await _bucketDir(bucket, createDir: createDir);
    final hash = sha256.convert(utf8.encode(key)).toString();
    return File('${folder.path}/$hash$_mp3Extension');
  }

  Future<({int files, int bytes})> _bucketStats(
    SpeechCacheBucket bucket,
  ) async {
    try {
      final folder = await _bucketDir(bucket, createDir: false);
      if (!folder.existsSync()) return (files: 0, bytes: 0);
      var files = 0;
      var bytes = 0;
      await for (final entity in folder.list()) {
        if (entity is! File || !entity.path.endsWith(_mp3Extension)) continue;
        final stat = entity.statSync();
        files += 1;
        bytes += stat.size;
      }
      return (files: files, bytes: bytes);
    } on Object {
      return (files: 0, bytes: 0);
    }
  }

  Future<void> _clearBucket(SpeechCacheBucket bucket) async {
    try {
      final folder = await _bucketDir(bucket, createDir: false);
      if (!folder.existsSync()) return;
      await for (final entity in folder.list()) {
        if (entity is File) _deleteQuietly(entity);
      }
    } on Object {
      // 目录不存在或单文件已被系统清理时继续完成。
    }
  }

  Future<List<_DiskAudioEntry>> _collectAllAudioEntries() async {
    final result = <_DiskAudioEntry>[];
    for (final bucket in SpeechCacheBucket.values) {
      await _appendBucketEntries(bucket, result);
    }
    return result;
  }

  Future<void> _appendBucketEntries(
    SpeechCacheBucket bucket,
    List<_DiskAudioEntry> out,
  ) async {
    try {
      final folder = await _bucketDir(bucket, createDir: false);
      if (!folder.existsSync()) return;
      await for (final entity in folder.list()) {
        if (entity is! File || !entity.path.endsWith(_mp3Extension)) continue;
        final stat = entity.statSync();
        out.add(_DiskAudioEntry(entity, stat.size, stat.modified));
      }
    } on Object {
      // 读取单桶失败不阻断另一桶的容量裁剪。
    }
  }

  Future<void> _touchQuietly(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // 某些只读或并发删除场景下更新时间失败无害。
    }
  }

  bool _deleteQuietly(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
        return true;
      }
      return false;
    } on FileSystemException {
      return false;
    }
  }
}

class _DiskAudioEntry {
  const new(this.file, this.size, this.modified);

  final File file;
  final int size;
  final DateTime modified;
}

class _NoopTestDiskCache implements SpeechDiskCachePort {
  const new();

  @override
  bool get isSupported => true;

  @override
  Future<Uint8List?> read(SpeechCacheBucket bucket, String key) async => null;

  @override
  Future<void> write(
    SpeechCacheBucket bucket,
    String key,
    Uint8List bytes,
  ) async {}

  @override
  Future<bool> contains(SpeechCacheBucket bucket, String key) async => false;

  @override
  Future<SpeechCacheStats> stats() async => SpeechCacheStats.empty;

  @override
  Future<void> clear({SpeechCacheBucket? bucket}) async {}

  @override
  Future<int> enforceLimit(int maxBytes) async => 0;
}
