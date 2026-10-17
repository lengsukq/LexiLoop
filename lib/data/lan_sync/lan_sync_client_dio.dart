/// 基于 HTTP 的局域网对端客户端。
///
/// **为什么不用一个「局域网同步」的包**：本需求只用到两个 GET，而 `dio`
/// 已经在依赖里、请求头与超时的处理方式也已定型（见 `webdav_client.dart`）。
/// 引入一个包换来的是「它怎么发请求、怎么报错」这套需要重新学的东西，
/// 而这份协议只有两个端点。
///
/// **为什么要传 `Dio` 进来**：与 `WebdavClient` 同理——替换 `HttpClientAdapter`
/// 就能拿到真实的请求构造（方法、路径、配对码请求头）而不发真网络请求。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 局域网对端客户端。
class LanSyncHttpClient implements LanSyncClient {
  /// 以目标设备与配对码构造（不传 `Dio` 则新建一个）。
  new(this._host, this._pairingCode, {Dio? dio}) : _dio = dio ?? _createDio();

  final DiscoveredLanHost _host;
  final String _pairingCode;
  final Dio _dio;

  @override
  Future<LanSyncHandshake> handshake() async {
    final response = await _send<String>(
      () => _dio.get<String>(
        _url(lanSyncHandshakePath),
        options: _options(
          responseType: ResponseType.plain,
          timeoutMs: lanSyncRequestTimeoutMs,
        ),
      ),
    );
    if (!_isSuccess(response)) throw _failureOf(response);
    final handshake = parseLanSyncHandshake(response.data ?? '');
    if (handshake == null) {
      // 对方应答了，但说的不是这套协议：地址被别的程序占了，
      // 或者中间有东西在改写响应。
      throw const ExternalServiceError(AppErrorCode.lanSyncNotSharing);
    }
    if (handshake.protocolVersion != lanSyncProtocolVersion) {
      throw const ExternalServiceError(AppErrorCode.lanSyncProtocolMismatch);
    }
    return handshake;
  }

  @override
  Future<LanSyncBackup> downloadBackup() async {
    final response = await _send<List<int>>(
      () => _dio.get<List<int>>(
        _url(lanSyncBackupPath),
        options: _options(
          responseType: ResponseType.bytes,
          timeoutMs: lanSyncTransferTimeoutMs,
        ),
      ),
    );
    if (!_isSuccess(response)) throw _failureOf(response);

    final bytes = response.data ?? const <int>[];
    if (bytes.isEmpty) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    // 声明的长度与实际的长度各校验一次：声明可以缺失、也可以撒谎。
    if (bytes.length > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '对端备份实际 ${bytes.length} 字节，上限 $maxBackupBytes',
      );
    }
    return LanSyncBackup(
      bytes: Uint8List.fromList(bytes),
      fileName: _headerOf(response, lanSyncBackupNameHeader) ?? '',
      totalRows: _intHeaderOf(response, lanSyncBackupRowsHeader),
    );
  }

  /// 目标路径的完整 URL。
  String _url(String path) => _host.baseUri.resolve(path).toString();

  /// 发起请求并把传输层异常归一化。
  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final mapped = mapDioFailure(error);
      // 浏览器的同源策略与「真的连不上」是两回事，原样上抛；
      // 其余（超时、连接被拒、对方中途关掉共享）统一归成「连不上对方」。
      if (mapped is ExternalServiceError &&
          mapped.code == AppErrorCode.browserCorsBlocked) {
        throw mapped;
      }
      throw ExternalServiceError(
        AppErrorCode.lanSyncUnreachable,
        isTransient: true,
        details: error.message,
      );
    }
  }

  /// 响应是否为 2xx。
  ///
  /// 不用 `Response.isSuccess`：本文件已经把 `validateStatus` 放开，
  /// 状态码的解释集中在这里更清楚。
  bool _isSuccess(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    return status >= lanSyncStatusSuccessFloor &&
        status < lanSyncStatusSuccessCeil;
  }

  /// 非 2xx 状态码对应的业务错误。
  AppError _failureOf(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    return switch (status) {
      lanSyncStatusUnauthorized => const ValidationError(
        AppErrorCode.lanSyncCodeInvalid,
      ),
      lanSyncStatusNotFound => const NotFoundError(
        AppErrorCode.lanSyncNotSharing,
      ),
      lanSyncStatusConflict => const ExternalServiceError(
        AppErrorCode.lanSyncBusy,
        isTransient: true,
      ),
      lanSyncStatusTooLarge => const ValidationError(
        AppErrorCode.backupTooLarge,
      ),
      _ => ExternalServiceError(
        AppErrorCode.lanSyncRequestFailed,
        isTransient: status >= lanSyncStatusServerErrorFloor,
        details: 'HTTP $status',
      ),
    };
  }

  /// 请求选项：配对码请求头、超时与「状态码不是异常」。
  Options _options({
    required int timeoutMs,
    required ResponseType responseType,
  }) => Options(
    responseType: responseType,
    headers: <String, String>{lanSyncCodeHeader: _pairingCode},
    // 与 `WebdavClient` 同一套约定：状态码是数据的一部分，
    // 由本文件按本协议的语义解释（401 是码错、409 是忙）。
    validateStatus: (status) => true,
    connectTimeout: Duration(milliseconds: timeoutMs),
    receiveTimeout: Duration(milliseconds: timeoutMs),
    sendTimeout: Duration(milliseconds: timeoutMs),
  );

  /// 某个响应头的值；缺失时返回 `null`。
  String? _headerOf(Response<Object?> response, String name) {
    final value = response.headers.value(name);
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  /// 某个响应头按整数解析；缺失或非数字时为 0。
  ///
  /// `0` 而不是 `null`：它只用于成功后的 SnackBar 文案，
  /// 让调用方为此处理一个可空值不值得。
  int _intHeaderOf(Response<Object?> response, String name) =>
      int.tryParse(_headerOf(response, name) ?? '') ?? 0;
}

/// 按本协议的需要构造 `Dio`。
///
/// 只设默认响应类型与「状态码不是异常」；配对码请求头逐请求带
/// （测试里能直接断言请求头）。
Dio _createDio() => Dio(
  BaseOptions(
    responseType: ResponseType.plain,
    validateStatus: (status) => true,
  ),
);
