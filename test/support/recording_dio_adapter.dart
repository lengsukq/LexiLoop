/// 记录请求并返回脚本化响应的 `dio` 传输层替身。
///
/// **为什么替换 `HttpClientAdapter` 而不是在端口层造假**：`WebdavClient` 的
/// 正确性有一半在「我们到底发了什么请求」——方法（`PROPFIND` / `MKCOL`）、
/// 路径（目录有没有补斜杠）、认证头、请求体、`Depth`。换掉传输层之后，
/// 这些都能断言，且不发真网络请求。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 一次被记录下来的请求。
class RecordedRequest {
  /// 以 method、uri、headers 与 body 构造。
  new({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  /// HTTP 方法（`PROPFIND` / `MKCOL` / `PUT` / `GET`）。
  final String method;

  /// 请求 URI（含查询串，本应用不用查询串）。
  final Uri uri;

  /// 请求头（键已小写化）。
  final Map<String, String> headers;

  /// 请求体字节（无请求体时为空）。
  final Uint8List body;

  /// 请求体按 UTF-8 解码后的文本。
  String get bodyText => utf8.decode(body, allowMalformed: true);

  /// 某个请求头（键大小写不敏感）。
  String? header(String name) => headers[name.toLowerCase()];
}

/// 脚本化响应。
class ScriptedResponse {
  /// 以状态码与响应体构造。
  const new({
    required this.statusCode,
    this.body = '',
    this.delay,
    this.failure,
    this.headers = const <String, String>{},
  });

  /// HTTP 状态码；传输层失败时为 0。
  final int statusCode;

  /// 响应体文本。
  final String body;

  /// 可选延迟；用来验证「超时 → `webdavUnreachable`」这条分支。
  final Duration? delay;

  /// 若非空，则抛出该类型的 [DioException] 而不返回响应。
  ///
  /// 用它精确模拟「连不上」与「超时」两条分支：真实的超时依赖
  /// `dio` 的适配器实现，在自定义适配器下并不可靠。
  final DioExceptionType? failure;

  /// 额外的响应头。
  ///
  /// 局域网同步把备份文件名与行数放在响应头里（握手不导出数据，
  /// 因此这两个信息只能在下载响应里带上），要断言它们就得能脚本化响应头。
  final Map<String, String> headers;
}

/// 记录请求并按队列返回响应的适配器。
///
/// 队列用尽后重复最后一项；队列为空时返回 200 空响应，
/// 于是只关心「请求长什么样」的用例不必排脚本。
final class RecordingDioAdapter implements HttpClientAdapter {
  /// 以响应脚本构造。
  new([List<ScriptedResponse> responses = const <ScriptedResponse>[]])
    : _responses = List<ScriptedResponse>.of(responses);

  final List<ScriptedResponse> _responses;

  /// 按调用顺序记录下来的请求。
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// 最近一次请求。
  RecordedRequest get last => requests.last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = await _readBody(requestStream);
    requests.add(
      RecordedRequest(
        method: options.method,
        uri: options.uri,
        headers: <String, String>{
          for (final entry in options.headers.entries)
            entry.key.toLowerCase(): '${entry.value}',
        },
        body: body,
      ),
    );

    final scripted = _next();
    final delay = scripted.delay;
    if (delay != null) await Future<void>.delayed(delay);

    final failure = scripted.failure;
    if (failure != null) {
      throw DioException(
        requestOptions: options,
        type: failure,
        error: '模拟传输层失败（$failure）',
      );
    }
    return ResponseBody.fromString(
      scripted.body,
      scripted.statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/plain'],
        for (final entry in scripted.headers.entries)
          entry.key: <String>[entry.value],
      },
    );
  }

  /// 取下一个脚本项：用尽后重复最后一项。
  ScriptedResponse _next() {
    if (_responses.isEmpty) return const ScriptedResponse(statusCode: 200);
    if (_responses.length == 1) return _responses.first;
    return _responses.removeAt(0);
  }

  /// 把请求流读成字节。
  Future<Uint8List> _readBody(Stream<Uint8List>? stream) async {
    if (stream == null) return Uint8List(0);
    final builder = BytesBuilder(copy: false);
    await stream.forEach(builder.add);
    return builder.takeBytes();
  }

  @override
  void close({bool force = false}) {}
}

/// 用给定脚本构造一个已装好替身的 `Dio`。
Dio dioWith(RecordingDioAdapter adapter, {Duration? connectTimeout}) {
  return Dio(
    BaseOptions(
      responseType: ResponseType.plain,
      connectTimeout: connectTimeout,
      receiveTimeout: connectTimeout,
      validateStatus: (status) => true,
    ),
  )..httpClientAdapter = adapter;
}
