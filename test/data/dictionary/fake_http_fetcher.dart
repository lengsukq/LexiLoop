/// 测试用的假 HTTP 客户端。
///
/// 全部网络调用都经由 `HttpFetcher` 注入，因此测试可以完全离线：
/// 这里按 URL 匹配返回预置响应，并记录调用序列供断言。
library;

import 'package:lexiloop/data/dictionary/http_fetcher.dart';

/// 按 URL 决定响应的假客户端。
class FakeHttpFetcher implements HttpFetcher {
  /// 以处理函数构造。
  new(this.handler);

  /// 按「URL + 请求体」产生响应；抛 [HttpFailure] 表示网络层失败。
  final Future<HttpFetchResponse> Function(String url, String? body) handler;

  /// 依次记录被调用的 URL。
  final List<String> calls = <String>[];

  /// 依次记录被调用的请求体（GET 为 `null`）。
  final List<String?> bodies = <String?>[];

  @override
  Future<HttpFetchResponse> get(
    String url, {
    required Duration timeout,
    Map<String, String>? headers,
  }) {
    calls.add(url);
    bodies.add(null);
    return handler(url, null);
  }

  @override
  Future<HttpFetchResponse> post(
    String url, {
    required String body,
    required Duration timeout,
    Map<String, String>? headers,
  }) {
    calls.add(url);
    bodies.add(body);
    return handler(url, body);
  }
}

/// 按 URL 子串匹配固定响应的假客户端。
FakeHttpFetcher routedFetcher(Map<String, HttpFetchResponse> routes) {
  return FakeHttpFetcher((url, body) async {
    for (final entry in routes.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return const HttpFetchResponse(statusCode: 404, body: '');
  });
}

/// 按调用次序依次返回响应的假客户端（用尽后重复最后一项）。
FakeHttpFetcher sequencedFetcher(List<HttpFetchResponse> responses) {
  var index = 0;
  return FakeHttpFetcher((url, body) async {
    final response = index < responses.length
        ? responses[index]
        : responses.last;
    index += 1;
    return response;
  });
}

/// 构造一个 JSON 响应。
HttpFetchResponse jsonResponse(String body, {int statusCode = 200}) =>
    HttpFetchResponse(statusCode: statusCode, body: body);
