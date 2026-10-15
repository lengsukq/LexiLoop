/// 提交前的本地正确性信号。
///
/// 对应旧版 `src/app/(main)/study/study-client.tsx` 的 `exactLocal`。
///
/// **它只服务一处判断**：用了提示却答得不完全正确时，把「记得 / 简单」降为
/// 「模糊」（见 `study_page.dart` 的 `_effectiveRating`）。服务层返回的判定
/// 仍然是唯一权威——这里判对判错都不会改变入库结果，因此允许它「宁松勿严」：
/// 只做字面比较，不引入编辑距离容错。容错是判题的事，混进降级判断会让
/// 「为什么这一档被改了」变得无法解释。
library;

import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/spelling.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/features/study/study_texts.dart';

/// 本地字面判定；`null` 表示「还没有作答」，无从判断。
bool? studyLocalExact({required StudyItemView item, required String answer}) {
  final trimmed = answer.trim();
  if (trimmed.isEmpty) return null;
  final word = item.word;
  final term = word.term;
  return switch (item.questionType) {
    // 看词说义没有客观作答，本地信号恒为「不知道」。
    QuestionType.enToZh => null,
    QuestionType.enToZhChoice => trimmed == studyMeaningText(word).trim(),
    QuestionType.zhToEnChoice ||
    QuestionType.listeningChoice ||
    QuestionType.letterBank ||
    QuestionType.clozeSentence => _sameTerm(trimmed, term, word.sourceLanguage),
    QuestionType.zhToEnSpelling || QuestionType.listeningSpelling =>
      word.contentType == LexicalContentType.sentence
          ? normalizeSentenceAnswer(trimmed) == normalizeSentenceAnswer(term)
          : _sameTerm(trimmed, term, word.sourceLanguage),
  };
}

/// 词条类答案的字面比较：走与判题同一个归一化，避免「本地说不同、服务说相同」。
bool _sameTerm(String answer, String term, String language) =>
    normalizeTerm(answer, language) == normalizeTerm(term, language);
