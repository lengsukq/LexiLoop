/// Android 系统分享（`ACTION_SEND text/plain`）桥接器。
///
/// 在其他应用（浏览器、新闻 App、阅读器）中选中一段英文或网页链接并分享给
/// LexiLoop 时，接收分享文本并导入文章智能分词页。非 Android 平台与测试环境
/// 下自动静默跳过，不会抛异常。
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// 接收系统分享文本的回调。
typedef SharedTextHandler = void Function(String text);

/// Android `ACTION_SEND` 分享通道桥接器。
class ShareIntentBridge {
  /// 以分享回调与可选自定义通道（供单测注入）构造。
  new({required this.onSharedText, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'lexiloop/share_intent';

  /// 收到非空分享文本或链接时的回调。
  final SharedTextHandler onSharedText;

  final MethodChannel _channel;
  bool _started = false;

  /// 是否在当前平台启用系统分享通道。
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 开始监听热启动分享，并拉取冷启动时的初始分享文本。
  Future<void> start({bool force = false}) async {
    if (_started || (!force && !isSupported)) return;
    _started = true;
    _channel.setMethodCallHandler(_handleCall);
    await _fetchInitial();
  }

  /// 释放通道监听。
  void dispose() {
    if (!_started) return;
    _started = false;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _fetchInitial() async {
    try {
      final initial = await _channel.invokeMethod<String>(
        'getInitialSharedText',
      );
      _dispatch(initial);
    } on MissingPluginException {
      debugPrint('ShareIntentBridge: 未注册原生分享通道，已跳过。');
    } on PlatformException catch (error) {
      debugPrint('ShareIntentBridge: 读取初始分享失败：${error.message}');
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'onSharedText') return;
    final arg = call.arguments;
    if (arg is String) _dispatch(arg);
  }

  void _dispatch(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return;
    onSharedText(text);
  }
}
