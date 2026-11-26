/// 一次发音请求。
///
/// **为什么是值对象而不是一堆参数**：界面层一次调用要传词条、口音、内容类型、
/// 播放设置与发音列表五项，铺开写参数既触顶又让调用点难以阅读；
/// 打包之后「发一次音」在代码里就是一句话。
library;

import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 一次发音请求。
class SpeechRequest {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.accent,
    required this.playback,
    this.contentType = LexicalContentType.word,
    this.pronunciations = const <PronunciationView>[],
  });

  /// 词条文本。
  final String term;

  /// 期望的口音。
  final Accent accent;

  /// 语速等播放设置。
  final PlaybackSettings playback;

  /// 内容类型，决定用哪档语速。
  final LexicalContentType contentType;

  /// 该词条的发音列表；为空表示没有真人录音可用。
  final List<PronunciationView> pronunciations;
}
