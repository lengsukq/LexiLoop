/// AI 选词的提示词构造。
///
/// 对应旧版 `src/modules/article-import/prompt.ts`（81 行）。
///
/// **为什么单独成文件**：提示词里的档位话术（`articleExamLevelHints`）是
/// 「AI 判断哪些词值得学」的唯一依据，改一个词就会改变整批推荐结果。
/// 把它与请求编排分开，才能对提示词单独写测试钉住。
///
/// 本文件必须保持纯 Dart。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 自适应档的水平要求话术。
final String articleAutoLevelHint = _join(<String>[
  '自适应档默认按 CET-4 及以上水平要求：A1-A2 基础词一律视为已知，不选；',
  '日常生活极常见词（如 water、snow、eat、big 之类小学词汇）无论出现多少次都不选；',
  '只选 B1 及以上、对理解文章关键且有学习价值的词。',
  '出现次数多不代表值得学，高频基础词直接排除。',
]);

/// 各考试目标的水平要求话术。
final Map<VocabularyLevel, String> articleExamLevelHints =
    <VocabularyLevel, String>{
      VocabularyLevel.gaokao: _join(<String>[
        '高考英语：A1 极基础词不选；',
        '重点选高中核心与 A2-B1 高频词。',
      ]),
      VocabularyLevel.cet4: _join(<String>[
        'CET-4（四级）：小学/初中极基础词不选；',
        '重点选四级核心词（CEFR B1-B2）。',
      ]),
      VocabularyLevel.cet6: _join(<String>[
        'CET-6（六级）：四级以下基础词视为已知，不选；',
        '重点选六级高频与进阶词（CEFR B2）。',
      ]),
      VocabularyLevel.ky: _join(<String>[
        '考研英语：B1 及以下基础词视为已知，不选；',
        '重点选考研高频学术词、熟词僻义与形近词（CEFR B2-C1）。',
      ]),
      VocabularyLevel.tem4: _join(<String>[
        'TEM-4（专四）：B1 基础词不选；',
        '重点选英语专业中高级核心词（CEFR B2-C1）。',
      ]),
      VocabularyLevel.tem8: _join(<String>[
        'TEM-8（专八）：B2 及以下视为已知，不选；',
        '重点选高级书面、文学与学术词汇（CEFR C1-C2）。',
      ]),
      VocabularyLevel.ielts: _join(<String>[
        '雅思 6.5–7.5+：B1 及以下视为已知，不选；',
        '重点选学术阅读/写作高频替换词（CEFR B2-C1）。',
      ]),
      VocabularyLevel.toefl: _join(<String>[
        '托福 90–105+：B1 及以下视为已知，不选；',
        '重点选学科科普与学术高频词（CEFR B2-C2）。',
      ]),
      VocabularyLevel.gre: _join(<String>[
        'GRE：B2 及以下常见词视为已知，不选；',
        '重点选高难抽象词、精准动词与低频书面词（CEFR C1-C2）。',
      ]),
    };

/// 一次提示词构造的输入。
class ArticlePromptInput {
  /// 以各字段构造。
  const new({
    required this.articleText,
    required this.candidates,
    required this.knownSample,
    required this.totalKnown,
    this.examTargets = const <VocabularyLevel>[],
    this.difficultyMode = ArticleDifficultyMode.atOrAbove,
    this.extractScope = ArticleExtractScope.wordsOnly,
  });

  /// 文章正文（内部会按 [articleSnippetChars] 截断）。
  final String articleText;

  /// 送进提示词的候选（仅作参考，LLM 可直接从正文提取并做词形还原）。
  final List<ArticlePromptCandidate> candidates;

  /// 已掌握词样本。
  final List<String> knownSample;

  /// 已掌握词总数。
  final int totalKnown;

  /// 考试目标（可多选，空表示自适应）。
  final List<VocabularyLevel> examTargets;

  /// 难度筛选模式（目标级别及以上 / 精准匹配该级别）。
  final ArticleDifficultyMode difficultyMode;

  /// 提取范围（仅分词 / 含短语与难句）。
  final ArticleExtractScope extractScope;
}

/// 一次请求的两段提示词。
class ArticleSelectionPrompt {
  /// 以各字段构造。
  const new({required this.systemPrompt, required this.userPrompt});

  /// 系统提示词。
  final String systemPrompt;

  /// 用户提示词。
  final String userPrompt;
}

/// 档位说明行。
String articleLevelLine(
  List<VocabularyLevel> examTargets, {
  ArticleDifficultyMode difficultyMode = ArticleDifficultyMode.atOrAbove,
}) {
  if (examTargets.isEmpty) {
    return '用户水平：自适应 — $articleAutoLevelHint';
  }
  final labels = examTargets.map((level) => level.wire).join('、');
  final hints = examTargets
      .map((level) => articleExamLevelHints[level] ?? articleAutoLevelHint)
      .join('；');
  final modeRule = difficultyMode == ArticleDifficultyMode.exactBand
      ? '筛选口径【精准匹配】：仅选取最贴合所选考试大纲的词汇，既排除更低级基础词，也尽量排除明显超出该考试范围的生僻词。'
      : '筛选口径【该级别及以上】：低于目标门槛的基础词不选，选取符合该级别及更高难度的有价值词汇；多档位时就高不就低。';
  return _join(<String>[
    '用户备考：$labels — $hints ',
    modeRule,
    '高频基础词无论出现多少次都不选。',
  ]);
}

/// 构造 AI 分词与选词提示词。
ArticleSelectionPrompt buildArticleSelectionPrompt(ArticlePromptInput input) {
  final snippet = input.articleText.length > articleSnippetChars
      ? input.articleText.substring(0, articleSnippetChars)
      : input.articleText;
  final sample = input.knownSample.take(articleKnownSampleLimit).join(', ');
  final candidates = jsonEncode(<Object?>[
    for (final candidate in input.candidates) candidate.toJson(),
  ]);
  final wordsOnly = input.extractScope == ArticleExtractScope.wordsOnly;
  return ArticleSelectionPrompt(
    systemPrompt: '你是专业英语分词与难度分级引擎。只输出严格有效的 JSON，不要输出解释或 markdown。',
    userPrompt: <String>[
      if (wordsOnly) _wordsOnlyIntroLine else _fullScopeIntroLine,
      articleLevelLine(input.examTargets, difficultyMode: input.difficultyMode),
      '用户已掌握词数：${input.totalKnown}，示例：${sample.isEmpty ? '无' : sample}',
      _rulesLine,
      '输出 JSON 格式（严格 JSON，无 trailing comma）：',
      if (wordsOnly) _wordOnlyJsonShapeLine else _jsonShapeLine,
      if (!wordsOnly) _constraintsLine,
      '',
      '<article>$snippet</article>',
      '<candidates>$candidates</candidates>',
    ].join('\n'),
  );
}

/// 仅分词模式的开场说明。
final String _wordsOnlyIntroLine = _join(<String>[
  '请直接阅读 <article> 正文进行智能分词与难度筛选，提取值得该用户学习的英文单词',
  '（查词释义将由有道词典完成，无需生成完整释义）。',
]);

/// 含短语与难句模式的开场说明。
final String _fullScopeIntroLine = _join(<String>[
  '请阅读 <article> 正文，选出值得该用户学习的英文单词、短语搭配与难句',
  '（单词详细释义将由有道词典完成）。',
]);

/// 筛选与词形还原规则。
final String _rulesLine = _join(<String>[
  '规则：1) 直接基于 <article> 分词，不要局限于 <candidates>（<candidates> 仅作频次参考）；',
  '2) 必须做词形还原：term 填标准词典原形（如 implemented→implement、companies→company），',
  'surface 填文章中的原始变形词（原文已是原形则填 null）；',
  '3) 已掌握词、停用词、纯专有名词与过简基础词不选；',
  '4) 无需输出完整词典释义，reason 只写 ≤16 字语境提示或选词依据，',
  'examTags 标出所属考试标签（如 ["CET6","IELTS"]），',
  '并给出准确的 cefrLevel、frequency 与 difficulty。',
]);

/// 仅分词模式的 JSON 形状示例。
final String _wordOnlyJsonShapeLine = _join(<String>[
  '{"words":[{"term":string,"surface":string|null,"reason":string,',
  '"difficulty":1-$articleAiDifficultyMax,',
  '"cefrLevel":"A1"|"A2"|"B1"|"B2"|"C1"|"C2"|null,',
  '"frequency":"VERY_COMMON"|"COMMON"|"NORMAL"|"RARE"|null,',
  '"examTags":string[]}]}',
]);

/// 数量与质量约束（含短语与难句模式）。
final String _constraintsLine = _join(<String>[
  '约束：phrases 0-$articlePhraseLimit 个，sentences 0-$articleSentenceLimit 个；',
  '短语如 because of 等固定搭配需包含 keyVocab 对每个词的词性与释义；',
  '句子的 grammar 需点出句型/从句；均给出直译与意译。',
]);

/// 完整模式 JSON 形状示例。
final String _jsonShapeLine = _join(<String>[
  '{"words":[{"term":string,"surface":string|null,"reason":string,',
  '"difficulty":1-$articleAiDifficultyMax,',
  '"cefrLevel":"A1"|"A2"|"B1"|"B2"|"C1"|"C2"|null,',
  '"frequency":"VERY_COMMON"|"COMMON"|"NORMAL"|"RARE"|null,',
  '"examTags":string[]}],',
  '"phrases":[{"term":string,"reason":string,',
  '"difficulty":1-$articleAiDifficultyMax,',
  '"cefrLevel":string|null,"literalTranslation":string,',
  '"freeTranslation":string,"keyVocab":[{"term":string,"pos":string|null,',
  '"meaning":string}],"grammar":{"pattern":string|null,"notes":string[]},',
  '"nuance":string|null}],',
  '"sentences":[{"sentence":string,"literalTranslation":string,',
  '"freeTranslation":string,"keyVocab":[{"term":string,"pos":string|null,',
  '"meaning":string}],"grammar":{"pattern":string|null,"notes":string[]},',
  '"nuance":string|null}]}',
]);

/// 拼接多段文案。
///
/// 提示词里的中文段落必须逐字符与旧版一致，因此拼接**不补任何分隔符**；
/// 用 `join()` 而不是相邻字符串字面量，是因为后者的「缺空格」会被
/// `missing_whitespace_between_adjacent_strings` 判定为笔误。
String _join(List<String> parts) => parts.join();
