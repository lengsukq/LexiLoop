/// 按运行平台选择音频播放器，浏览器不依赖 dart:io。
library;

export 'just_audio_engine_web.dart'
    if (dart.library.io) 'just_audio_engine_native.dart';
