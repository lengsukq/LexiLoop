/// 音频字节下载。
///
/// 单独成接口的理由与 `HttpFetcher` 相同：词典查询与音频下载的失败语义不同
/// （前者要按 provider 策略重试，后者只要「拿不到就顺延下一个发音引擎」），
/// 复用同一个客户端抽象会逼调用方理解两套错误处理。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';

/// 音频字节下载的抽象。
abstract interface class AudioDownloadPort {
  /// 下载音频字节；失败必须抛出，由上层决定如何顺延。
  Future<Uint8List> download(Uri url);
}

/// 基于 `Dio` 的 [AudioDownloadPort] 实现。
final class DioAudioDownloader implements AudioDownloadPort {
  /// 以可选客户端构造。
  ///
  /// 默认配置带浏览器的 `user-agent` 与 `accept` 头以及 10 秒超时
  /// （[dictionaryProviderTimeoutMs]），并校验返回内容确实为音频而非错误页。
  new({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              responseType: ResponseType.bytes,
              followRedirects: true,
              connectTimeout: const Duration(
                milliseconds: dictionaryProviderTimeoutMs,
              ),
              receiveTimeout: const Duration(
                milliseconds: dictionaryProviderTimeoutMs,
              ),
              headers: const <String, String>{
                'user-agent': audioUserAgent,
                'accept': audioAcceptHeader,
              },
            ),
          );

  final Dio _client;

  @override
  Future<Uint8List> download(Uri url) async {
    final response = await _client.get<List<int>>(url.toString());
    final contentType =
        response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty || _isNonAudioPayload(contentType)) {
      throw ExternalServiceError(
        AppErrorCode.providerTransientFailure,
        details: url.toString(),
      );
    }
    return Uint8List.fromList(bytes);
  }

  /// 拦截有道错误 JSON、网关 HTML 页等非音频响应，避免脏数据写进缓存。
  bool _isNonAudioPayload(String contentType) =>
      contentType.startsWith('text/') ||
      contentType.startsWith('application/json') ||
      contentType.startsWith('application/xml');
}
