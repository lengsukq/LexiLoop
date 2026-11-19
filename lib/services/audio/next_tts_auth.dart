/// Next.js 音频服务登录会话。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lexiloop/core/constants.dart';

/// 将登录密码存储在操作系统提供的安全存储中。
class NextTtsCredentials {
  /// 创建凭据存储。
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _key = 'lexiloop_next_tts_password';

  /// 读取已保存的密码。
  Future<String?> read() => _storage.read(key: _key);

  /// 保存或清除密码。
  Future<void> save(String value) => value.isEmpty
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

/// 复用 Next.js 登录接口返回的会话来下载 MP3。
class NextTtsAuthenticatedClient {
  /// 创建客户端。
  new({Dio? client, NextTtsCredentials? credentials})
    : _client = client ?? Dio(),
      credentials = credentials ?? NextTtsCredentials();

  final Dio _client;

  /// 平台安全存储。
  final NextTtsCredentials credentials;
  final Map<String, String> _sessions = <String, String>{};

  /// 通过网站的标准登录 API 获取会话。
  Future<bool> login(Uri origin) async {
    final password = await credentials.read();
    if (password == null || password.isEmpty) return false;
    final response = await _client.post<Object?>(
      origin.resolve('/api/auth/login').toString(),
      data: <String, String>{'password': password},
      options: Options(
        contentType: Headers.jsonContentType,
        validateStatus: (status) =>
            status != null && status < ttsHttpServerErrorFloor,
      ),
    );
    if (response.statusCode != ttsHttpStatusOk) return false;
    final cookies = response.headers.map['set-cookie'] ?? <String>[];
    for (final cookie in cookies) {
      final pair = cookie.split(';').first;
      if (pair.startsWith('lexiloop_auth=')) {
        _sessions[origin.origin] = pair;
        return true;
      }
    }
    return false;
  }

  /// 请求音频，401 时自动登录一次后重试。
  Future<Uint8List?> download(Uri url) async {
    var response = await _fetch(url);
    if (response.statusCode == ttsHttpStatusUnauthorized) {
      final authenticated = await login(url.replace(path: '/'));
      if (!authenticated) return null;
      response = await _fetch(url);
    }
    if (response.statusCode != ttsHttpStatusOk || response.data == null) {
      return null;
    }
    final contentType = response.headers.value(Headers.contentTypeHeader) ?? '';
    if (!contentType.startsWith('audio/')) return null;
    return Uint8List.fromList(response.data!);
  }

  Future<Response<List<int>>> _fetch(Uri url) => _client.get<List<int>>(
    url.toString(),
    options: Options(
      responseType: ResponseType.bytes,
      headers: <String, String>{
        if (_sessions.containsKey(url.origin)) 'Cookie': _sessions[url.origin]!,
      },
      validateStatus: (status) =>
          status != null && status < ttsHttpServerErrorFloor,
    ),
  );
}
