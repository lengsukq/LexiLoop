/// 词书包多通道下载器：支持目录刷新、通道测速、自动回退与 SHA-256 强校验。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';

/// 下载进度回调（已接收字节、总字节；未知总长时 `total` 为 `-1`）。
typedef WordPackProgressCallback = void Function(int received, int total);

/// 取消令牌抽象，避免领域/服务层直接耦合 `dio.CancelToken`。
class WordPackCancelSignal {
  /// 创建取消信号。
  new();

  final CancelToken _dioToken = CancelToken();

  /// 是否已请求取消。
  bool get isCancelled => _dioToken.isCancelled;

  /// 触发取消。
  void cancel() {
    if (!_dioToken.isCancelled) _dioToken.cancel('user_cancelled');
  }

  /// 供 `Dio` 使用的底层令牌。
  CancelToken get dioToken => _dioToken;
}

/// 词书包原始字节拉取端口（测试可替换为内存假实现）。
abstract interface class WordPackHttpPort {
  /// 拉取目标 URL 的字节内容。
  Future<Uint8List> getBytes(
    String url, {
    required int timeoutMs,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  });

  /// 探测目标 URL 是否可达并返回耗时（毫秒）；不可达返回 `null`。
  Future<int?> probeLatency(String url, {required int timeoutMs});
}

/// 基于 `Dio` 的默认下载端口。
class DioWordPackHttpPort implements WordPackHttpPort {
  /// 以可选的 `Dio` 实例构造。
  new([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              headers: const <String, String>{'User-Agent': audioUserAgent},
              responseType: ResponseType.bytes,
              followRedirects: true,
            ),
          );

  final Dio _dio;

  @override
  Future<Uint8List> getBytes(
    String url, {
    required int timeoutMs,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        cancelToken: cancel?.dioToken,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          connectTimeout: Duration(milliseconds: timeoutMs),
          receiveTimeout: Duration(milliseconds: timeoutMs),
          validateStatus: (code) =>
              code != null && code >= httpStatusOkMin && code < httpStatusOkMax,
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const ExternalServiceError(
          AppErrorCode.wordPackDownloadFailed,
          isTransient: true,
        );
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const ValidationError(AppErrorCode.wordPackCancelled);
      }
      throw ExternalServiceError(
        AppErrorCode.wordPackDownloadFailed,
        isTransient: true,
        details: error.message ?? error.type.name,
      );
    }
  }

  @override
  Future<int?> probeLatency(String url, {required int timeoutMs}) async {
    final watch = Stopwatch()..start();
    try {
      await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          connectTimeout: Duration(milliseconds: timeoutMs),
          receiveTimeout: Duration(milliseconds: timeoutMs),
          validateStatus: (code) =>
              code != null && code >= httpStatusOkMin && code < httpStatusOkMax,
        ),
      );
      watch.stop();
      return watch.elapsedMilliseconds;
    } on DioException {
      watch.stop();
      return null;
    }
  }
}

/// 单个通道的测速结果。
class ChannelProbeResult {
  /// 以通道类型、延迟（毫秒）与目标 URL 构造。
  const new({required this.kind, required this.latencyMs, required this.url});

  /// 通道类型。
  final WordPackChannelKind kind;

  /// 延迟毫秒数；不可达时为 `null`。
  final int? latencyMs;

  /// 探测的目录地址。
  final String url;

  /// 是否连通。
  bool get reachable => latencyMs != null;
}

/// 词书包下载成功结果。
class DownloadedWordPack {
  /// 以字节、校验和与最终命中的通道地址构造。
  const new({
    required this.bytes,
    required this.sha256Hex,
    required this.resolvedUrl,
  });

  /// 原始文件字节。
  final Uint8List bytes;

  /// 实际计算出的 SHA-256（小写十六进制）。
  final String sha256Hex;

  /// 最终成功下载的 URL。
  final String resolvedUrl;
}

/// 词书包多通道下载器。
class WordPackDownloader {
  /// 以底层 HTTP 端口构造。
  const new(this._http);

  final WordPackHttpPort _http;

  /// 从远端多通道拉取最新 `catalog.json`；全部通道失败时返回 `null`。
  Future<WordPackCatalog?> fetchRemoteCatalog(
    WordPackDownloadConfig config,
  ) async {
    final urls = resolveWordPackUrls(
      config: config,
      relativePath: wordPackCatalogRelativePath,
    );
    for (final url in urls) {
      try {
        final bytes = await _http.getBytes(
          url,
          timeoutMs: wordPackChannelProbeTimeoutMs,
        );
        return WordPackCatalog.parse(utf8.decode(bytes));
      } on AppError {
        continue;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  /// 并发探测各内置通道对 `catalog.json` 的可达性与延迟。
  Future<List<ChannelProbeResult>> probeChannels(
    WordPackDownloadConfig config,
  ) {
    final targets = <WordPackChannelKind>[
      WordPackChannelKind.jsdelivrGcore,
      WordPackChannelKind.jsdelivrFastly,
      WordPackChannelKind.ghfast,
      WordPackChannelKind.ghproxy,
      WordPackChannelKind.githubDirect,
      if (config.customBaseUrl.trim().isNotEmpty) WordPackChannelKind.custom,
    ];
    return Future.wait<ChannelProbeResult>(
      targets.map((kind) => _probeSingle(kind, config)),
    );
  }

  /// 下载指定词书包并校验体积与 SHA-256；自动模式按通道顺位回退。
  Future<DownloadedWordPack> downloadPack({
    required WordPackCatalogItem item,
    required WordPackDownloadConfig config,
    String? repo,
    String? ref,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) {
    final urls = resolveWordPackUrls(
      config: config,
      relativePath: item.relativePath,
      repo: repo,
      ref: ref,
    );
    if (urls.isEmpty) {
      throw const ExternalServiceError(AppErrorCode.wordPackDownloadFailed);
    }
    return _downloadWithFallback(
      urls: urls,
      expectedSha256: item.sha256,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<ChannelProbeResult> _probeSingle(
    WordPackChannelKind kind,
    WordPackDownloadConfig config,
  ) async {
    final url = buildChannelUrl(
      kind: kind,
      repo: config.effectiveRepo,
      ref: config.effectiveRef,
      relativePath: wordPackCatalogRelativePath,
      customBaseUrl: config.customBaseUrl,
    );
    if (url.isEmpty) {
      return ChannelProbeResult(kind: kind, latencyMs: null, url: url);
    }
    final latency = await _http.probeLatency(
      url,
      timeoutMs: wordPackChannelProbeTimeoutMs,
    );
    return ChannelProbeResult(kind: kind, latencyMs: latency, url: url);
  }

  Future<DownloadedWordPack> _downloadWithFallback({
    required List<String> urls,
    required String expectedSha256,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) async {
    AppError? lastError;
    for (final url in urls) {
      if (cancel?.isCancelled ?? false) {
        throw const ValidationError(AppErrorCode.wordPackCancelled);
      }
      try {
        return await _downloadSingle(
          url: url,
          expectedSha256: expectedSha256,
          onProgress: onProgress,
          cancel: cancel,
        );
      } on AppError catch (error) {
        if (error.code == AppErrorCode.wordPackCancelled) rethrow;
        lastError = error;
      }
    }
    throw lastError ??
        const ExternalServiceError(AppErrorCode.wordPackDownloadFailed);
  }

  Future<DownloadedWordPack> _downloadSingle({
    required String url,
    required String expectedSha256,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) async {
    final bytes = await _http.getBytes(
      url,
      timeoutMs: wordPackDownloadTimeoutMs,
      onProgress: onProgress,
      cancel: cancel,
    );
    if (bytes.length > wordPackMaxCompressedBytes) {
      throw const ValidationError(AppErrorCode.wordPackTooLarge);
    }
    final digest = sha256.convert(bytes).toString().toLowerCase();
    final expected = expectedSha256.trim().toLowerCase();
    if (expected.isNotEmpty && digest != expected) {
      throw ValidationError(
        AppErrorCode.wordPackChecksumMismatch,
        details: 'expected=$expected actual=$digest url=$url',
      );
    }
    return DownloadedWordPack(
      bytes: bytes,
      sha256Hex: digest,
      resolvedUrl: url,
    );
  }
}
