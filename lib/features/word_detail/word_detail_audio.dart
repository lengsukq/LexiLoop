/// 词条详情与词库列表的发音入口。
///
/// **为什么统一走这里**：详情页头部、发音栏、例句行与列表卡片四处都要
/// 发音，每处各写一遍「读设置 → 组请求 → 处理结果」必然漂移。
/// 所有发音策略（多选引擎优先级与失败顺延）完全收口在 `WordSpeaker` 内。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';

/// 朗读一段文本，并把失败或自动顺延提示给用户。
///
/// [accent] 为空时用设置里的默认口音（`playback.defaultAccent`）：
/// 列表卡片与例句没有「按口音切换」的交互，让每个调用点各自解析默认值
/// 只会多出几份一模一样的兜底逻辑。
Future<void> speakWithWordSpeaker({
  required BuildContext context,
  required WidgetRef ref,
  required String term,
  Accent? accent,
  LexicalContentType contentType = LexicalContentType.word,
  List<PronunciationView> pronunciations = const <PronunciationView>[],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final playback =
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;
  final effectiveAccent = accent ?? playback.defaultAccent;
  final result = await ref
      .read(wordSpeakerProvider)
      .speak(
        SpeechRequest(
          term: term,
          accent: effectiveAccent,
          playback: playback,
          contentType: contentType,
          pronunciations: pronunciations,
        ),
      );
  final message = _messageOf(result);
  if (message != null && context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 结果对应的用户提示；无需提示时返回 `null`。
String? _messageOf(SpeechResult result) => switch (result) {
  SpeechFailed(:final error) => error.message,
  _ when result.fellBack =>
    '${result.fellBackFrom!.label}暂不可用，已自动切换为${result.playedSource!.label}',
  _ => null,
};
