/// 打开 Android 系统的文字转语音设置。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('lexiloop/system_speech_settings');

/// 进入系统语音引擎/语音包设置；不可用时给出操作提示。
Future<void> openSystemSpeechSettings(BuildContext context) async {
  var opened = false;
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      opened = await _channel.invokeMethod<bool>('open') ?? false;
    } on PlatformException {
      opened = false;
    } on MissingPluginException {
      opened = false;
    }
  }
  if (!context.mounted || opened) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('系统语音设置'),
      content: const Text(
        '请在系统设置中搜索「文字转语音」或「语音合成」，'
        '选择可用引擎并下载英语（美国 / 英国）语音包。也可以在这里改用「词典在线发音」。',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
