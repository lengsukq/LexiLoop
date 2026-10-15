/// 音频层测试共用的构造辅助。
library;

import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/speech_request.dart';

/// 一份中性播放设置，供测试免去逐项填写。
const PlaybackSettings testPlaybackSettings = PlaybackSettings.defaults;

/// 构造一条发音请求。
SpeechRequest speechRequest({
  String term = 'apple',
  Accent accent = Accent.us,
  List<PronunciationView> pronunciations = const <PronunciationView>[],
  LexicalContentType contentType = LexicalContentType.word,
}) => SpeechRequest(
  term: term,
  accent: accent,
  playback: testPlaybackSettings,
  contentType: contentType,
  pronunciations: pronunciations,
);

/// 构造一条带音标与音频地址的发音。
PronunciationView pronunciation({
  Accent accent = Accent.us,
  String? audioUrl,
  String? source,
  String phonetic = 'ˈæpəl',
}) => PronunciationView(
  accent: accent,
  phonetic: phonetic,
  audioUrl: audioUrl,
  source: source,
);
