/// 学习页的发音编排。
///
/// 把「按设置挑口音与语速、真人录音优先、把结果翻译成界面提示」从按钮组件里
/// 拆出来（旧版这些判断散在 `lib/tts-client.ts` 与详情页 hook 里）：按钮只负责
/// 点按与弹提示，发音策略可以脱离 widget 树测试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';

/// 进入题目后自动朗读前的延迟（毫秒）。
///
/// 与旧版学习页的自动播放、游戏页的 `gameAutoSpeakDelayMs` 同一量级：
/// 等首帧动画与路由过渡落定，避免声音抢在画面之前。
const int studyAutoSpeakDelayMs = 220;

/// 自动朗读会直接放出答案的题型。
///
/// **不照抄旧版**：旧版只在选择题里跳过自动播放，于是「根据释义拼写英文」
/// 这类题一进来就把单词念出来，题目本身就失效了。这里按「听到发音会不会
/// 泄露答案」划界：看词说义/看词选义/听音类可以播，其余不播。
const Set<QuestionType> studyAutoSpeakSilentTypes = <QuestionType>{
  QuestionType.zhToEnChoice,
  QuestionType.zhToEnSpelling,
  QuestionType.clozeSentence,
  QuestionType.letterBank,
};

/// 预取时向前看的题数。
///
/// 与旧版 `src/app/(main)/study/study-client.tsx` 的
/// `preloadTtsBatch(items.slice(index, index + 5))` 一致：**含当前题**共 5 条。
/// 含当前题不是笔误——当前题的发音最可能被点开，预热它收益最大。
const int studyPreloadAheadCount = 5;

/// 为词条构造一次发音请求。
///
/// 口音来自设置而不是写死 `US`（旧版学习页把 `"US"` 硬编码进了预取调用）：
/// 设置页已经能选英音，写死会让选了英音的用户在点击前预取到美音录音，
/// 点了才发现声音不对。
SpeechRequest studySpeechRequest({
  required StudyWordView word,
  required Accent accent,
  required PlaybackSettings playback,
}) => SpeechRequest(
  term: word.term,
  accent: accent,
  playback: playback,
  contentType: word.contentType,
  pronunciations: word.pronunciations,
);

/// 按当前设置朗读一个词条，返回需要提示给用户的文案；无需提示时返回 `null`。
///
/// 真人录音成功就不打扰用户；回落到系统朗读必须**说出来**（否则用户会以为
/// 词典音频坏了）；两者都没响时把错误自带的中文文案透出去。
Future<String?> studySpeakTerm({
  required WordSpeaker speaker,
  required SpeechRequest request,
  required bool humanAudioEnabled,
}) async {
  speaker.humanAudioEnabled = humanAudioEnabled;
  final result = await speaker.speak(request);
  return switch (result) {
    HumanRecordingPlayed() => null,
    // 用户自己关掉真人录音时不必提示：那不是降级，是他选的行为。
    SystemVoicePlayed() => humanAudioEnabled ? '暂无真人录音，已改用系统朗读' : null,
    SpeechFailed(:final error) => error.message,
  };
}

/// 预取「接下来若干题」的真人录音。
///
/// 只预热、不播放。这里**不**再包一层错误处理：`WordSpeaker.preloadBatch`
/// 按地址去重、限制并发，单条失败由缓存层吸收（`AudioCache.resolve` 从不抛），
/// 多一层 `catch` 只会变成静默吞异常。
void studyPreloadAhead({
  required WordSpeaker speaker,
  required Iterable<StudyItemView> items,
  required Accent accent,
  required PlaybackSettings playback,
}) {
  speaker.humanAudioEnabled = playback.humanAudioEnabled;
  final requests = <SpeechRequest>[
    for (final item in items)
      studySpeechRequest(word: item.word, accent: accent, playback: playback),
  ];
  if (requests.isEmpty) return;
  unawaited(speaker.preloadBatch(requests));
}

/// 该题型是否允许自动朗读（是否真的播还取决于设置开关）。
bool studyAutoSpeakAllowed(QuestionType type) =>
    !studyAutoSpeakSilentTypes.contains(type);

/// 进入题目时静默播放一次发音。
///
/// 自动播放是背景行为，不弹「已改用系统朗读」之类的提示：用户并没有点任何
/// 东西，每换一题冒一条 SnackBar 会把答题节奏切碎。失败也只是没声音，
/// 页面上仍有朗读按钮可以重试。
void studyAutoSpeak({
  required WordSpeaker speaker,
  required PlaybackSettings playback,
  required Accent accent,
  required StudyItemView item,
}) {
  if (!playback.autoPlayPronunciation) return;
  if (!studyAutoSpeakAllowed(item.questionType)) return;
  speaker.humanAudioEnabled = playback.humanAudioEnabled;
  unawaited(
    speaker.speak(
      studySpeechRequest(word: item.word, accent: accent, playback: playback),
    ),
  );
}

/// 朗读一个词条，并把「降级 / 失败」提示给用户。
///
/// 界面层唯一的发音入口：朗读按钮、提示区的重播、快捷键 `R` 共用它，
/// 三处各写一套提示必然漂移。播放设置在这里读，调用点因此不必认识
/// `appSettingsProvider`。
Future<void> speakStudyWord(
  BuildContext context,
  WidgetRef ref, {
  required StudyWordView word,
  required Accent accent,
}) async {
  final playback =
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;
  final messenger = ScaffoldMessenger.of(context);
  final message = await studySpeakTerm(
    speaker: ref.read(wordSpeakerProvider),
    request: studySpeechRequest(word: word, accent: accent, playback: playback),
    humanAudioEnabled: playback.humanAudioEnabled,
  );
  if (message == null) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
