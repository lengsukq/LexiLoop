/// 词条详情页的展示格式化。
///
/// 标签映射集中一处：旧版把状态、题型、语言的显示名散在多个组件里各写一遍，
/// 改一处忘一处。这里全部是纯函数，可脱离 Widget 单测。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 内容类型的中文名。
String contentTypeLabel(LexicalContentType type) => switch (type) {
  LexicalContentType.word => '单词',
  LexicalContentType.phrase => '短语',
  LexicalContentType.sentence => '句子',
};

/// 语种代码的中文名；未收录的语言直接回显代码，不显示空白。
String languageLabel(String code) => switch (code.toLowerCase()) {
  'en' => '英语',
  'zh' => '中文',
  'ja' => '日语',
  'ko' => '韩语',
  'fr' => '法语',
  'de' => '德语',
  'es' => '西班牙语',
  'it' => '意大利语',
  'pt' => '葡萄牙语',
  'ru' => '俄语',
  'nl' => '荷兰语',
  _ => code,
};

/// 内容来源的中文名。
String contentSourceLabel(ContentSource source) => switch (source) {
  ContentSource.aiOnly => 'AI 生成',
  ContentSource.mixed => 'AI + 词典',
  ContentSource.dictionaryOnly => '词典',
};

/// 复习评级的中文名。
String ratingLabel(ReviewRating rating) => switch (rating) {
  ReviewRating.again => '重来',
  ReviewRating.hard => '模糊',
  ReviewRating.good => '良好',
  ReviewRating.easy => '轻松',
};

/// 题型的中文名。
String questionTypeLabel(QuestionType type) => switch (type) {
  QuestionType.enToZh => '英译中（自评）',
  QuestionType.enToZhChoice => '英译中选择',
  QuestionType.zhToEnChoice => '中译英选择',
  QuestionType.zhToEnSpelling => '中译英拼写',
  QuestionType.listeningSpelling => '听音拼写',
  QuestionType.clozeSentence => '例句填空',
  QuestionType.listeningChoice => '听音选择',
  QuestionType.letterBank => '字母拼词',
};

/// 本地时间 `2026-03-01 10:05`。
///
/// 手写格式化而不引 `intl` 的 `DateFormat`：这里只需要一种固定格式，
/// 引入 locale 初始化反而会带来「未初始化即抛错」的额外失败面。
String formatTimestamp(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.year}-${_pad(date.month)}-${_pad(date.day)} '
      '${_pad(date.hour)}:${_pad(date.minute)}';
}

/// 作答耗时；缺失或非正数显示为 `—`。
String formatDuration(int? millis) {
  if (millis == null || millis <= 0) return '—';
  return '${(millis / 1000).toStringAsFixed(1)} 秒';
}

/// 天数字段；缺失显示为 `—`。
String formatDays(int? days) => days == null ? '—' : '$days 天';

/// 稳定性（天）；缺失显示为 `—`。
String formatStability(double? days) =>
    days == null ? '—' : '${days.toStringAsFixed(1)} 天';

/// FSRS 难度；缺失显示为 `—`。
String formatDifficulty(double? value) =>
    value == null ? '—' : value.toStringAsFixed(2);

/// FSRS 阶段的中文名；未知序号显示为 `—`。
///
/// 序号语义与旧版 `ts-fsrs` 对齐，取值来自 `core/constants.dart` 的
/// `fsrsState*` 具名常量，避免在界面层再写一遍裸数字。
String fsrsStateLabel(int? state) => switch (state) {
  fsrsStateNew => '新卡',
  fsrsStateLearning => '学习中',
  fsrsStateReview => '复习中',
  fsrsStateRelearning => '重学中',
  _ => '—',
};

/// 累计正确率；从未作答时返回 `null`，由界面显示「暂无作答记录」。
String? formatAccuracy(
  double? accuracy, {
  required int correct,
  required int total,
}) {
  if (accuracy == null) return null;
  return '${(accuracy * 100).round()}%（$correct/$total）';
}

/// 按设置口音挑选发音；没有匹配项时退回第一条，仍为空则返回 `null`。
///
/// 「取不到就第一条」而不是显示空白：音标属于词条的基本信息，
/// 有英音没美音时用户仍应看到音标。
PronunciationView? preferredPronunciation(
  List<PronunciationView> items,
  Accent accent,
) {
  if (items.isEmpty) return null;
  for (final item in items) {
    if (item.accent == accent) return item;
  }
  return items.first;
}

String _pad(int value) => value.toString().padLeft(2, '0');
