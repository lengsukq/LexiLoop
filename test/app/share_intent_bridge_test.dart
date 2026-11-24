/// Android 系统分享桥接器的单元测试。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/share_intent_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lexiloop/share_intent_test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('冷启动读取初始分享文本，并过滤空白内容', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getInitialSharedText') {
            return '  https://example.com/article  ';
          }
          return null;
        });

    final received = <String>[];
    final bridge = ShareIntentBridge(
      onSharedText: received.add,
      channel: channel,
    );
    await bridge.start(force: true);
    bridge.dispose();

    expect(received, <String>['https://example.com/article']);
  });

  test('热启动推送 onSharedText 触发回调', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    final received = <String>[];
    final bridge = ShareIntentBridge(
      onSharedText: received.add,
      channel: channel,
    );
    await bridge.start(force: true);

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('onSharedText', 'Shared English paragraph.'),
          ),
          (_) {},
        );
    bridge.dispose();

    expect(received, <String>['Shared English paragraph.']);
  });

  test('原生端未注册通道时静默跳过不抛错', () async {
    const missing = MethodChannel('lexiloop/share_intent_unregistered');
    final received = <String>[];
    final bridge = ShareIntentBridge(
      onSharedText: received.add,
      channel: missing,
    );

    await bridge.start(force: true);
    bridge.dispose();

    expect(received, isEmpty);
  });
}
