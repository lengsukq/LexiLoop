/// 学习界面的文案与展示格式。
///
/// 集中在一处而不是散落在各组件里：同一段文案（例如「记得」）会同时出现在
/// 自评按钮、判定反馈与会话总结中，分散维护必然漂移。
///
/// 这里只放**纯函数**，不碰 Flutter 的构建上下文，便于单独断言。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 一分钟的秒数。
///
/// `core/constants.dart` 只有毫秒常量，而这里做的是「毫秒 → 分:秒」的
/// 展示换算，单位不同，硬套毫秒常量反而更难读。
const int _secondsPerMinute = 60;

/// 一个月按多少天估算（用于「N 月」档）。
const int _daysPerMonth = 30;

/// 一年按多少天估算（用于「X.X 年」档）。
const int _daysPerYear = 365;

/// 使用提示后的说明文案（尚未揭示答案时）。
const String studyHintPendingText = '已使用提示，本题将按「模糊」记录';

/// 使用提示后的说明文案（已揭示答案时）。
const String studyHintRevealedText = '已使用提示，建议选择「模糊」';

/// 把 FSRS 间隔天数格式化为评级按钮下方的短文案。
///
/// 与旧版 `study-client.tsx` 的 `formatInterval` 一致：不足一天「今天」、
/// 不足一月按天、不足一年按月、再往上按年。按钮只有一行位置，写成
/// 「3 天后」会挤掉等级本身。
String studyIntervalText(int scheduledDays) {
  if (scheduledDays < 1) return '今天';
  if (scheduledDays == 1) return '1 天';
  if (scheduledDays < _daysPerMonth) return '$scheduledDays 天';
  if (scheduledDays < _daysPerYear) {
    return '${(scheduledDays / _daysPerMonth).round()} 月';
  }
  return '${(scheduledDays / _daysPerYear).toStringAsFixed(1)} 年';
}

/// 四档自评的中文文案。
String studyRatingLabel(ReviewRating rating) => switch (rating) {
  ReviewRating.again => '忘了',
  ReviewRating.hard => '模糊',
  ReviewRating.good => '记得',
  ReviewRating.easy => '简单',
};

/// 题头的作答指令。
///
/// 旧版题头是一个题型徽章（「看词选义」），它说明「这是什么题」却不说
/// 「现在该做什么」。对用户来说，后者才是进入一道题时需要的那句话。
String studyQuestionInstruction(QuestionType type) => switch (type) {
  QuestionType.enToZh => '回忆它的含义',
  QuestionType.enToZhChoice => '选择正确的释义',
  QuestionType.zhToEnChoice => '根据释义选择单词',
  QuestionType.zhToEnSpelling => '根据释义拼写英文',
  QuestionType.listeningSpelling => '听发音拼写单词',
  QuestionType.clozeSentence => '补全句子中的单词',
  QuestionType.listeningChoice => '听发音选择单词',
  QuestionType.letterBank => '根据释义拼出单词',
};

/// 揭示后的判定文案。
///
/// `null` 表示主观题（看词说义）没有客观对错，只能给参考答案。
String studyVerdictText({required bool? isCorrect}) => isCorrect == null
    ? '参考答案'
    : isCorrect
    ? '回答正确'
    : '回答错误';

/// 选择题里「算作正确」的那个选项文本。
///
/// 定义题的正确项是释义串，其余题的正确项是词条本身。选项文本由
/// `question_builder` 用 [studyMeaningText] 同一套拼接生成，因此这里能得到
/// 与服务层 `expectedAnswer` 相同的字符串。
String studyChoiceAnswer(StudyItemView item) => switch (item.questionType) {
  QuestionType.enToZhChoice => studyMeaningText(item.word),
  _ => item.word.term,
};

/// 题干用的中文释义。
///
/// 目标语言释义按 `；` 连接；一条都没有时回退到句子类词条的整句翻译——
/// 句子常常只有翻译没有逐词释义，只认释义会让句子复习变成空白题。
String studyMeaningText(StudyWordView word) {
  final text = targetDefinitionTexts(word.definitions, word.targetLanguage);
  if (text.isNotEmpty) return text;
  return word.translation?.trim() ?? '';
}

/// 按设置中的口音取音标；该口音缺失时回退到第一条发音。
String? studyPhonetic(StudyWordView word, Accent accent) {
  for (final item in word.pronunciations) {
    if (item.accent == accent) return item.phonetic;
  }
  return word.pronunciations.isEmpty
      ? null
      : word.pronunciations.first.phonetic;
}

/// 把毫秒格式化为 `m:ss`。
///
/// 用「分:秒」而不是「x 分 y 秒」：总结卡片的数字要能一眼扫过，
/// 时长的量级本来就只有几分钟。
String studyDurationText(int? durationMs) {
  final totalSeconds = (durationMs ?? 0) ~/ secondMs;
  final minutes = totalSeconds ~/ _secondsPerMinute;
  final seconds = totalSeconds % _secondsPerMinute;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// 正确率文案：`correctCount / max(1, completedCount)`。
///
/// 分母兜底为 1 而不是 0：一道没做就结束会话时，显示 `NaN%` 比显示 `0%`
/// 更让人困惑。
String studyAccuracyText(int correctCount, int completedCount) {
  final denominator = completedCount <= 0 ? 1 : completedCount;
  final percent = (correctCount * 100 / denominator).round();
  return '$percent%';
}

/// 把任意异常转换成可展示的中文提示。
///
/// 只有 [AppError] 带面向用户的文案，其余异常直接把 `toString()` 附在后面：
/// 吞掉它们会让「界面没反应」变成无法定位的问题。
String studyErrorMessage(Object error) =>
    error is AppError ? error.message : '操作失败：$error';
