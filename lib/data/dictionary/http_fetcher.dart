/// 可注入的 HTTP 抽象。
///
/// **为什么不让 provider 直接 new `Dio()`**：任务要求全部网络调用可注入，
/// 否则测试只能发真实请求。`Dio` 本身也能替换 `HttpClientAdapter`，但那个
/// 接口要构造 `ResponseBody`/`RequestOptions` 一堆类型；本抽象只有
/// 「方法 + URL + 头 + 超时」，测试里一个内存 Map 就能假冒。
library;

import 'package:dio/dio.dart';

/// 网络失败的类别。
///
/// 只区分「超时」与「连不上」两类：这两类在调用方映射成不同的
/// `AppErrorCode`（超时算瞬时失败，连不上是明确的网络不可用），
/// 而 HTTP 状态码由 [HttpFetchResponse] 承载，不需要走异常。
enum HttpFailureKind {
  /// 连接、发送或读取超时。
  timeout,

  /// 无法建立连接（离线、DNS 失败、连接被拒绝）。
  network,
}

/// 网络层失败。
///
/// 用独立的异常类型而不是直接抛 `DioException`，是为了让 provider 与
/// LLM 客户端不依赖 `dio` 的具体异常层级——换 HTTP 库时只需改本文件。
class HttpFailure implements Exception {
  /// 以类别与原因构造。
  const new(this.kind, {this.detail});

  /// 失败类别。
  final HttpFailureKind kind;

  /// 原始异常，仅用于日志。
  final Object? detail;

  @override
  String toString() => 'HttpFailure(${kind.name}): ${detail ?? ''}';
}

/// 一次 HTTP 响应。
class HttpFetchResponse {
  /// 以状态码与响应体构造。
  const new({required this.statusCode, required this.body});

  /// HTTP 状态码。
  final int statusCode;

  /// 响应体文本。
  final String body;

  /// 状态码是否表示成功（2xx）。
  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// 可注入的 HTTP 客户端。
abstract interface class HttpFetcher {
  /// 发起 GET。
  ///
  /// 非 2xx **不抛异常**：状态码是数据的一部分（404 表示「词条不存在」，
  /// 429 表示限流，语义完全不同），由调用方判断。
  Future<HttpFetchResponse> get(
    String url, {
    required Duration timeout,
    Map<String, String>? headers,
  });

  /// 发起 POST。
  Future<HttpFetchResponse> post(
    String url, {
    required String body,
    required Duration timeout,
    Map<String, String>? headers,
  });
}

/// 基于 `dio` 的默认实现。
class DioHttpFetcher implements HttpFetcher {
  /// 以可选的 `Dio` 实例构造（不传则新建）。
  new({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<HttpFetchResponse> get(
    String url, {
    required Duration timeout,
    Map<String, String>? headers,
  }) => _send(() => _dio.get<String>(url, options: _options(timeout, headers)));

  @override
  Future<HttpFetchResponse> post(
    String url, {
    required String body,
    required Duration timeout,
    Map<String, String>? headers,
  }) => _send(
    () =>
        _dio.post<String>(url, data: body, options: _options(timeout, headers)),
  );

  Options _options(Duration timeout, Map<String, String>? headers) => Options(
    responseType: ResponseType.plain,
    headers: headers,
    connectTimeout: timeout,
    receiveTimeout: timeout,
    sendTimeout: timeout,
    // 状态码由调用方解释，Dio 不应把它变成异常。
    validateStatus: (status) => true,
  );

  Future<HttpFetchResponse> _send(
    Future<Response<String>> Function() request,
  ) async {
    try {
      final response = await request();
      return HttpFetchResponse(
        statusCode: response.statusCode ?? 0,
        body: response.data ?? '',
      );
    } on DioException catch (error) {
      throw HttpFailure(_kindOf(error), detail: error);
    }
  }

  HttpFailureKind _kindOf(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout => HttpFailureKind.timeout,
    DioExceptionType.badCertificate ||
    DioExceptionType.badResponse ||
    DioExceptionType.cancel ||
    DioExceptionType.connectionError ||
    DioExceptionType.unknown => HttpFailureKind.network,
  };
}
