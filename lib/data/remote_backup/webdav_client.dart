/// 基于 HTTP/WebDAV 协议的远端备份实现。
///
/// **为什么不用现成的 WebDAV 包**：本需求只用到 4 个方法（`PROPFIND` / `MKCOL` /
/// `PUT` / `GET`），而 `dio` 已经在依赖里、请求头与超时的处理方式也已定型；
/// 引入一个包换来的是「它怎么发请求、怎么报错」这套需要重新学的东西。
///
/// **为什么要传 `Dio` 进来**：`dio` 的 `HttpClientAdapter` 是官方留出的传输层
/// 接缝，测试用它就能拿到真实的请求构造（方法、路径、认证头、请求体）而不发
/// 真网络请求——比在端口层造假更能钉住「我们真的按 WebDAV 说话」。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_client.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/data/remote_backup/webdav_multistatus.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

/// `PROPFIND` 的请求体。
///
/// 只索取三个属性：`resourcetype` 用来区分目录与文件，另外两个用来展示。
/// 写成固定字符串而不是让 `xml` 包生成：请求体是常量，生成一次的结果不会变。
const String webdavPropfindBody =
    '<?xml version="1.0" encoding="utf-8"?>'
    ' <d:propfind xmlns:d="DAV:"><d:prop>'
    ' <d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
    ' </d:prop></d:propfind>';

/// WebDAV 客户端。
class WebdavClient implements RemoteBackupClient {
  /// 以凭据与可选的 `Dio` 构造（不传则按 WebDAV 的参数新建）。
  new(this._credential, {Dio? dio}) : _dio = dio ?? _createDio();

  final WebdavCredential _credential;
  final Dio _dio;

  /// 表单里的「测试连接」：确认目录可用。
  ///
  /// 与 [ensureDirectory] 是同一件事，但语义不同——界面按钮点它之后
  /// 什么都不会变，因此单独给一个名字而不是让界面假装在「上传前的准备」。
  Future<void> testConnection() => ensureDirectory();

  @override
  Future<void> ensureDirectory() async {
    final directory = _credential.directoryUri;
    final existing = await _send<String>(
      () => _dio.request<String>(
        directory.toString(),
        data: webdavPropfindBody,
        options: _options(
          method: 'PROPFIND',
          headers: <String, String>{'depth': '0'},
          timeoutMs: webdavRequestTimeoutMs,
        ),
      ),
    );
    if (_isSuccess(existing)) return;
    if (!_isMissingDirectory(existing)) throw _failureOf(existing);
    for (final uri in _credential.directoryChain()) {
      await _createDirectory(uri);
    }
  }

  @override
  Future<void> putBackup({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final response = await _send<void>(
      () => _dio.put<void>(
        _credential.fileUri(fileName).toString(),
        data: Stream<List<int>>.value(bytes),
        options: _options(
          headers: <String, String>{
            'content-type': backupMimeType,
            'content-length': '${bytes.length}',
          },
          timeoutMs: webdavUploadTimeoutMs,
        ),
      ),
    );
    if (!_isSuccess(response)) throw _failureOf(response);
  }

  @override
  Future<List<RemoteBackupEntry>> listBackups() async {
    final response = await _send<String>(
      () => _dio.request<String>(
        _credential.directoryUri.toString(),
        data: webdavPropfindBody,
        options: _options(
          method: 'PROPFIND',
          headers: <String, String>{'depth': '1'},
          timeoutMs: webdavRequestTimeoutMs,
        ),
      ),
    );
    if (!_isSuccess(response)) throw _failureOf(response);
    return parseWebdavBackups(response.data ?? '');
  }

  @override
  Future<Uint8List> downloadBackup(RemoteBackupEntry entry) async {
    // 列表里的字节数是服务器的声明，不能作为唯一依据（可以缺失，也可以撒谎），
    // 但它能在「远端放了一份 2GB 的文件」时挡住第一波内存分配——
    // 下载之后还有一次按实际长度的复核。
    if (entry.sizeBytes > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '远端备份声明 ${entry.sizeBytes} 字节，上限 $maxBackupBytes',
      );
    }
    final response = await _send<List<int>>(
      () => _dio.get<List<int>>(
        _credential.fileUri(entry.name).toString(),
        options: _options(
          responseType: ResponseType.bytes,
          timeoutMs: webdavUploadTimeoutMs,
        ),
      ),
    );
    if (!_isSuccess(response)) throw _failureOf(response);
    final bytes = response.data ?? const <int>[];
    if (bytes.isEmpty) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    if (bytes.length > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '远端备份实际 ${bytes.length} 字节，上限 $maxBackupBytes',
      );
    }
    return Uint8List.fromList(bytes);
  }

  /// 建一个目录；已存在（405）视为成功。
  Future<void> _createDirectory(Uri uri) async {
    final response = await _send<void>(
      () => _dio.request<void>(
        uri.toString(),
        options: _options(method: 'MKCOL', timeoutMs: webdavRequestTimeoutMs),
      ),
    );
    // 405 Method Not Allowed 是 RFC 4918 里「该集合已存在」的标准回答；
    // 部分服务用 301 表示同名集合存在，两者都当作成功。
    if (_isSuccess(response) || _isAlreadyExists(response)) return;
    throw _failureOf(response);
  }

  /// 发起请求并把传输层异常归一化。
  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      final mapped = mapDioFailure(error);
      // 浏览器的同源策略与我们自己的业务错误码是两回事，原样上抛；
      // 其余（超时、连不上）统一归成 WebDAV 的可读文案。
      if (mapped is ExternalServiceError &&
          mapped.code == AppErrorCode.browserCorsBlocked) {
        throw mapped;
      }
      throw ExternalServiceError(
        AppErrorCode.webdavUnreachable,
        isTransient: true,
        details: error.message,
      );
    }
  }

  /// 响应是否为 2xx。
  ///
  /// 不用 `Response.isSuccess`：该扩展在 `dio` 5.x 的 `Response` 上不存在，
  /// 而本文件已经把 `validateStatus` 放开，状态码判断集中在这里更清楚。
  bool _isSuccess(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    return status >= webdavStatusSuccessFloor &&
        status < webdavStatusSuccessCeil;
  }

  /// 目录不存在（还没有建）。
  bool _isMissingDirectory(Response<Object?> response) =>
      response.statusCode == webdavStatusNotFound;

  /// 目录已存在。
  bool _isAlreadyExists(Response<Object?> response) =>
      response.statusCode == webdavStatusMethodNotAllowed ||
      response.statusCode == webdavStatusMovedPermanently;

  /// 非 2xx 状态码对应的业务错误。
  AppError _failureOf(Response<Object?> response) {
    final status = response.statusCode ?? 0;
    if (status == webdavStatusUnauthorized || status == webdavStatusForbidden) {
      return const ExternalServiceError(AppErrorCode.webdavAuthFailed);
    }
    if (status == webdavStatusNotFound) {
      return const NotFoundError(AppErrorCode.webdavNotFound);
    }
    final transient = status >= webdavStatusServerErrorFloor;
    return ExternalServiceError(
      AppErrorCode.webdavRequestFailed,
      isTransient: transient,
      details: 'HTTP $status',
    );
  }

  /// 请求选项：认证头、超时与「状态码不是异常」。
  Options _options({
    required int timeoutMs,
    String? method,
    Map<String, String>? headers,
    ResponseType? responseType,
  }) => Options(
    method: method,
    responseType: responseType,
    headers: <String, String>{'authorization': _authorization, ...?headers},
    // 与 `DioHttpFetcher` 同一套约定：状态码是数据的一部分，
    // 由本文件按 WebDAV 的语义解释（401 是鉴权、404 是没建目录）。
    validateStatus: (status) => true,
    connectTimeout: Duration(milliseconds: timeoutMs),
    receiveTimeout: Duration(milliseconds: timeoutMs),
    sendTimeout: Duration(milliseconds: timeoutMs),
  );

  /// HTTP Basic 认证头。
  String get _authorization {
    final raw = '${_credential.username}:${_credential.password}';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }
}

/// 按 WebDAV 的需要构造 `Dio`。
///
/// 只设默认响应类型与超时；认证头逐请求带（测试里能直接断言请求头）。
Dio _createDio() => Dio(
  BaseOptions(
    responseType: ResponseType.plain,
    // WebDAV 的 207 与 405 都需要本层解释，不能变成异常。
    validateStatus: (status) => true,
  ),
);

/// 2xx 的下界（含）。
const int webdavStatusSuccessFloor = 200;

/// 2xx 的上界（不含）。
const int webdavStatusSuccessCeil = 300;

/// 鉴权失败。
const int webdavStatusUnauthorized = 401;

/// 禁止访问（部分服务用它表示密码错）。
const int webdavStatusForbidden = 403;

/// 目标不存在。
const int webdavStatusNotFound = 404;

/// 该集合已存在（MKCOL 的标准回答）。
const int webdavStatusMethodNotAllowed = 405;

/// 同名集合已存在（部分服务的回答）。
const int webdavStatusMovedPermanently = 301;

/// 服务端错误的起点。
const int webdavStatusServerErrorFloor = 500;
