/// AI 选词的结构化结果模型。
///
/// 对应旧版 `modules/article-import/ai-select.ts` 的 `AiSelectResult` 与
/// `schema.ts` 的 `AiSelectionItem` / `AiPhraseItem` / `AiSentenceItem`。
///
/// **为什么把「失败」也建模成结果而不是异常**：旧版 `aiSelectTerms` 把
/// 失败原因塞进 `AiSelectResult.error`，调用方一律继续走本地回退。
/// 若改成抛异常，「AI 没配」这条**正常**路径就会被迫在调用点写 try/catch，
/// 且很容易有人把 catch 写成「静默返回空候选」——那正是本模块最不能出的错。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';

/// AI 选出的一个单词。
class ArticleAiWord {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.reason,
    required this.difficulty,
    this.surfaceForm,
    this.cefrLevel,
    this.frequency,
    this.examTags = const <String>[],
  });

  /// 词典原形（lemma）。
  final String term;

  /// 原文中出现的变形词（与原形相同时可为 `null`）。
  final String? surfaceForm;

  /// 语境提示 / 推荐理由。
  final String reason;

  /// 难度（1–5）。
  final int difficulty;

  /// CEFR 等级。
  final String? cefrLevel;

  /// 词频档。
  final String? frequency;

  /// 考试标签（如 `CET6`、`IELTS`）。
  final List<String> examTags;
}

/// AI 选出的一个短语。
class ArticleAiPhrase {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.reason,
    required this.difficulty,
    required this.literalTranslation,
    required this.freeTranslation,
    this.cefrLevel,
    this.keyVocab = const <ArticleAiKeyVocab>[],
    this.grammarPattern,
    this.grammarNotes = const <String>[],
    this.nuance,
  });

  /// 短语文本。
  final String term;

  /// 推荐理由。
  final String reason;

  /// 难度（1–5）。
  final int difficulty;

  /// CEFR 等级。
  final String? cefrLevel;

  /// 直译。
  final String literalTranslation;

  /// 意译。
  final String freeTranslation;

  /// 重点词汇。
  final List<ArticleAiKeyVocab> keyVocab;

  /// 语法句型。
  final String? grammarPattern;

  /// 语法说明。
  final List<String> grammarNotes;

  /// 辨析。
  final String? nuance;

  /// 转成展示卡片。
  ArticleAiCard toCard() => ArticleAiCard(
    literalTranslation: literalTranslation,
    freeTranslation: freeTranslation,
    keyVocab: keyVocab,
    grammarPattern: grammarPattern,
    grammarNotes: grammarNotes,
    nuance: nuance,
  );
}

/// AI 选出的一个句子。
class ArticleAiSentence {
  /// 以各字段构造。
  const new({
    required this.sentence,
    required this.literalTranslation,
    required this.freeTranslation,
    this.keyVocab = const <ArticleAiKeyVocab>[],
    this.grammarPattern,
    this.grammarNotes = const <String>[],
    this.nuance,
  });

  /// 句子原文。
  final String sentence;

  /// 直译。
  final String literalTranslation;

  /// 意译。
  final String freeTranslation;

  /// 重点词汇。
  final List<ArticleAiKeyVocab> keyVocab;

  /// 语法句型。
  final String? grammarPattern;

  /// 语法说明。
  final List<String> grammarNotes;

  /// 注释。
  final String? nuance;

  /// 转成展示卡片。
  ArticleAiCard toCard() => ArticleAiCard(
    literalTranslation: literalTranslation,
    freeTranslation: freeTranslation,
    keyVocab: keyVocab,
    grammarPattern: grammarPattern,
    grammarNotes: grammarNotes,
    nuance: nuance,
  );
}

/// 一次 AI 选词的结果。
class ArticleAiSelection {
  /// 以各字段构造。
  const new({
    required this.applied,
    this.words = const <ArticleAiWord>[],
    this.phrases = const <ArticleAiPhrase>[],
    this.sentences = const <ArticleAiSentence>[],
    this.errorCode,
    this.error,
  });

  /// 成功结果。
  const new success({
    this.words = const <ArticleAiWord>[],
    this.phrases = const <ArticleAiPhrase>[],
    this.sentences = const <ArticleAiSentence>[],
  }) : applied = true,
       errorCode = null,
       error = null;

  /// 以失败原因构造。
  const new failure({
    required AppErrorCode this.errorCode,
    required String this.error,
  }) : applied = false,
       words = const <ArticleAiWord>[],
       phrases = const <ArticleAiPhrase>[],
       sentences = const <ArticleAiSentence>[];

  /// 空结果（未发起请求时使用）。
  static const ArticleAiSelection none = ArticleAiSelection(applied: false);

  /// AI 是否成功返回并解析出了结构。
  final bool applied;

  /// 选出的单词。
  final List<ArticleAiWord> words;

  /// 选出的短语。
  final List<ArticleAiPhrase> phrases;

  /// 选出的句子。
  final List<ArticleAiSentence> sentences;

  /// 失败的错误码（供程序判断；界面展示 [error]）。
  final AppErrorCode? errorCode;

  /// 失败原因（面向用户的中文文案）。
  final String? error;

  /// 是否返回了任何内容。
  bool get hasContent =>
      words.isNotEmpty || phrases.isNotEmpty || sentences.isNotEmpty;
}

/// 送进 AI 提示词的候选。
///
/// **为什么不直接序列化 [ArticleCandidate]**：旧版 `service.ts` 只把
/// `term` / `normalizedTerm` / `occurrences` / `sourceSentence` 四项发给模型，
/// 多送 `status`、`aiReason` 这些内部字段既费 token 又可能干扰判断。
class ArticlePromptCandidate {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.occurrences,
    this.sourceSentence,
  });

  /// 展示用词形。
  final String term;

  /// 归一化词形。
  final String normalizedTerm;

  /// 出现次数。
  final int occurrences;

  /// 出处句。
  final String? sourceSentence;

  /// 转成提示词里的 JSON 对象。
  ///
  /// 出处句为空时**不带这个键**（旧版传 `undefined`，`JSON.stringify` 会略过），
  /// 保持与旧版逐字节相同的候选载荷。
  Map<String, Object?> toJson() {
    final sentence = sourceSentence?.trim() ?? '';
    return <String, Object?>{
      'term': term,
      'normalizedTerm': normalizedTerm,
      'occurrences': occurrences,
      if (sentence.isNotEmpty) 'sourceSentence': sentence,
    };
  }
}
