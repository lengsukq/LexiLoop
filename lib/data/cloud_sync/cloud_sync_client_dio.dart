/// 基于 `Dio` + GZip 后台编解码的 Next.js 云端同步 HTTP 客户端。
///
/// 通过条件导出的 `lan_sync_codec.dart` 实现全平台兼容：
/// - 原生端（macOS / Android）自动启用后台 Isolate GZip 压缩上传与解压；
/// - Web 端自动退化为明文 JSON 传输，且不手动设置浏览器禁止的 `Accept-Encoding`。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_codec.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';

/// Next.js 云端同步客户端的 `Dio` 实现。
class CloudSyncHttpClient implements CloudSyncClient {
  /// 以服务器凭据构造（可注入自定义 `Dio` 供离线单测拦截请求）。
  new(this._credential, {Dio? dio}) : _dio = dio ?? _createDio();

  final CloudSyncCredential _credential;
  final Dio _dio;

  @override
  Future<CloudSyncHandshakeReply> handshake(
    CloudSyncHandshakeRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final result = await _postJson(
      path: cloudSyncHandshakePath,
      payload: request.toJson(),
      timeoutMs: cloudSyncRequestTimeoutMs,
      compressRequest: false,
      cancelSignal: cancelSignal,
    );
    return parseCloudSyncHandshakeReply(unwrapCloudSyncData(result.body));
  }

  @override
  Future<CloudSyncPullPage> pullPage(
    CloudSyncPullRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final result = await _postJson(
      path: cloudSyncPullPath,
      payload: request.toJson(),
      timeoutMs: cloudSyncTransferTimeoutMs,
      compressRequest: false,
      cancelSignal: cancelSignal,
    );
    return parseCloudSyncPullPage(
      unwrapCloudSyncData(result.body),
      wireBytes: result.responseBytes,
    );
  }

  @override
  Future<CloudSyncPushReply> pushBatch(
    CloudSyncPushRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final result = await _postJson(
      path: cloudSyncPushPath,
      payload: request.toJson(),
      timeoutMs: cloudSyncTransferTimeoutMs,
      compressRequest: true,
      cancelSignal: cancelSignal,
    );
    return parseCloudSyncPushReply(
      unwrapCloudSyncData(result.body),
      wireBytes: result.requestBytes,
    );
  }

  Future<({Map<String, Object?> body, int requestBytes, int responseBytes})>
  _postJson({
    required String path,
    required Map<String, Object?> payload,
    required int timeoutMs,
    required bool compressRequest,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final url = _resolveUrl(path);
    final encoded = await _encodeBody(payload, compress: compressRequest);
    final cancelToken = _bridgeCancel(cancelSignal);
    final response = await _sendBytes(
      url: url,
      body: encoded.bytes,
      options: _buildOptions(timeoutMs: timeoutMs, isGzipBody: encoded.isGzip),
      cancelToken: cancelToken,
    );
    final rawResponse = Uint8List.fromList(response.data ?? const <int>[]);
    if (!_isSuccess(response)) {
      throw await _failureOf(response, rawResponse);
    }
    final decoded = await decodeJsonObjectMaybeGzip(rawResponse);
    return (
      body: decoded,
      requestBytes: encoded.bytes.length,
      responseBytes: rawResponse.length,
    );
  }

  Future<({Uint8List bytes, bool isGzip})> _encodeBody(
    Map<String, Object?> payload, {
    required bool compress,
  }) async {
    if (compress) {
      final encoded = await encodeJsonGzipWithStats(payload);
      return (
        bytes: encoded.compressedBytes,
        isGzip: isLanSyncGzipBytes(encoded.compressedBytes),
      );
    }
    return (
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      isGzip: false,
    );
  }

  Future<Response<List<int>>> _sendBytes({
    required String url,
    required Uint8List body,
    required Options options,
    required CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<List<int>>(
        url,
        data: body,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      throw _mapDioError(error);
    }
  }

  AppError _mapDioError(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      return const ValidationError(AppErrorCode.cloudSyncCancelled);
    }
    final mapped = mapDioFailure(error);
    if (mapped is ExternalServiceError &&
        mapped.code == AppErrorCode.browserCorsBlocked) {
      return mapped;
    }
    return ExternalServiceError(
      AppErrorCode.cloudSyncUnreachable,
      isTransient: true,
      details: error.message,
    );
  }

  Future<AppError> _failureOf(
    Response<List<int>> response,
    Uint8List rawBytes,
  ) async {
    final status = response.statusCode ?? 0;
    final errorCode = await _tryReadErrorCode(rawBytes);
    if (errorCode == 'SYNC_PROTOCOL_MISMATCH') {
      return const ExternalServiceError(AppErrorCode.cloudSyncProtocolMismatch);
    }
    if (status == lanSyncStatusUnauthorized ||
        status == cloudSyncStatusForbidden) {
      return const ValidationError(AppErrorCode.cloudSyncAuthFailed);
    }
    if (status == lanSyncStatusTooLarge) {
      return const ValidationError(AppErrorCode.cloudSyncPayloadTooLarge);
    }
    if (status == lanSyncStatusNotFound) {
      return const ExternalServiceError(
        AppErrorCode.cloudSyncUnreachable,
        details: 'HTTP 404',
      );
    }
    return ExternalServiceError(
      AppErrorCode.cloudSyncRequestFailed,
      isTransient: status >= lanSyncStatusServerErrorFloor,
      details: 'HTTP $status ${errorCode ?? ''}'.trim(),
    );
  }

  Future<String?> _tryReadErrorCode(Uint8List rawBytes) async {
    if (rawBytes.isEmpty) return null;
    try {
      final decoded = await decodeJsonObjectMaybeGzip(rawBytes);
      return extractCloudSyncErrorCode(decoded);
    } on Object {
      return null;
    }
  }

  String _resolveUrl(String path) {
    final base = normalizeCloudSyncBaseUrl(_credential.baseUrl);
    if (base == null) {
      throw const ValidationError(AppErrorCode.cloudSyncInvalidUrl);
    }
    return '$base$path';
  }

  Options _buildOptions({required int timeoutMs, required bool isGzipBody}) =>
      Options(
        responseType: ResponseType.bytes,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=utf-8',
          if (isGzipBody) 'Content-Encoding': 'gzip',
          if (!PlatformCaps.isWeb) 'Accept-Encoding': 'gzip',
          if (_credential.password.isNotEmpty)
            cloudSyncPasswordHeader: _credential.password,
        },
        validateStatus: (status) => true,
        connectTimeout: Duration(milliseconds: timeoutMs),
        receiveTimeout: Duration(milliseconds: timeoutMs),
        sendTimeout: Duration(milliseconds: timeoutMs),
      );

  bool _isSuccess(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    return status >= lanSyncStatusSuccessFloor &&
        status < lanSyncStatusSuccessCeil;
  }

  CancelToken? _bridgeCancel(CloudSyncCancelSignal? signal) {
    if (signal == null) return null;
    if (signal.isCancelled) {
      throw const ValidationError(AppErrorCode.cloudSyncCancelled);
    }
    final token = CancelToken();
    signal.addListener(() {
      if (!token.isCancelled) token.cancel('cancelled');
    });
    return token;
  }
}

Dio _createDio() => Dio(
  BaseOptions(
    responseType: ResponseType.bytes,
    validateStatus: (status) => true,
  ),
);
