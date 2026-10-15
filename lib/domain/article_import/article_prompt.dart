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
      VocabularyLevel.cet4: _join(<String>[
        'CET-4：A1-B1 基础词视为已知，不选；',
        '重点选 B2 及以上。',
      ]),
      VocabularyLevel.cet6: _join(<String>[
        'CET-6：B1 及以下视为已知，不选；',
        '重点选 B2-C1。',
      ]),
      VocabularyLevel.ky: _join(<String>[
        '考研：B1 及以下视为已知，不选；',
        '重点选 B2-C1 学术/形近易混词。',
      ]),
      VocabularyLevel.ielts: _join(<String>[
        '雅思 6.5+：B2 及以下视为已知，不选；',
        '重点选 C1-C2 与学术词汇。',
      ]),
      VocabularyLevel.toefl: _join(<String>[
        '托福 90+：B2 及以下视为已知，不选；',
        '重点选 C1-C2 学术与低频词。',
      ]),
    };

/// 一次提示词构造的输入。
///
/// **`examTargets` 由调用方解析好再传进来**：旧版 `prompt.ts` 里还有一条
/// 「回退到 `vocabularyLevel`」的分支，但设置层保证 `examTargets` 恒为数组
/// （默认 `[]`），该分支在旧版与本版都不可达，故不在此重复。
class ArticlePromptInput {
  /// 以各字段构造。
  const new({
    required this.articleText,
    required this.candidates,
    required this.knownSample,
    required this.totalKnown,
    this.examTargets = const <VocabularyLevel>[],
  });

  /// 文章正文（内部会按 [articleSnippetChars] 截断）。
  final String articleText;

  /// 送进提示词的候选。
  final List<ArticlePromptCandidate> candidates;

  /// 已掌握词样本。
  final List<String> knownSample;

  /// 已掌握词总数。
  final int totalKnown;

  /// 考试目标（可多选，空表示自适应）。
  final List<VocabularyLevel> examTargets;
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
String articleLevelLine(List<VocabularyLevel> examTargets) {
  if (examTargets.isEmpty) {
    return '用户水平：自适应 — $articleAutoLevelHint';
  }
  final labels = examTargets.map((level) => level.wire).join('、');
  final hints = examTargets
      .map((level) => articleExamLevelHints[level] ?? articleAutoLevelHint)
      .join('；');
  return _join(<String>[
    '用户备考：$labels — $hints ',
    '多档位时就高不就低，按最高档位划线，低档基础词不选；',
    '高频基础词无论出现多少次都不选。',
  ]);
}

/// 构造 AI 选词提示词。
ArticleSelectionPrompt buildArticleSelectionPrompt(ArticlePromptInput input) {
  final snippet = input.articleText.length > articleSnippetChars
      ? input.articleText.substring(0, articleSnippetChars)
      : input.articleText;
  final sample = input.knownSample.take(articleKnownSampleLimit).join(', ');
  final candidates = jsonEncode(<Object?>[
    for (final candidate in input.candidates) candidate.toJson(),
  ]);
  return ArticleSelectionPrompt(
    systemPrompt: '只输出有效 JSON，不要输出任何解释或 markdown。',
    userPrompt: <String>[
      '你是词汇与句法筛选助手。结合文章语境与候选词，选出值得该用户学习的单词、短语与句子。',
      articleLevelLine(input.examTargets),
      '用户已掌握词数：${input.totalKnown}，示例：${sample.isEmpty ? '无' : sample}',
      _rulesLine,
      '输出 JSON 格式（严格 JSON，无 trailing comma）：',
      _jsonShapeLine,
      _constraintsLine,
      '',
      '<article>$snippet</article>',
      '<candidates>$candidates</candidates>',
    ].join('\n'),
  );
}

/// 筛选规则。
final String _rulesLine = _join(<String>[
  '规则：已掌握/过于常见/停用词不选；出现次数多不代表值得学，高频基础词直接排除；',
  '优先选对理解文章关键且对该水平有学习价值的内容；每个 reason/nuance 不超过 24 字。',
  '选出的单词 words 必须带上准确的 cefrLevel 与 frequency，便于按水平过滤；',
  '拿不准是 A1/A2 基础词时宁可不选。',
]);

/// 数量与质量约束。
final String _constraintsLine = _join(<String>[
  '约束：phrases 0-$articlePhraseLimit 个，sentences 0-$articleSentenceLimit 个；',
  '短语如 because of 等固定搭配需包含 keyVocab 对 each 词的词性与释义；',
  '句子的 grammar 需点出句型/从句；均给出直译与意译。',
]);

/// JSON 形状示例。
///
/// 与旧版逐字符一致（含字段顺序），只把难度区间改成引用
/// `articleAiDifficultyMax`，避免常量调整后提示词与实际校验脱节。
final String _jsonShapeLine = _join(<String>[
  '{"words":[{"term":string,"reason":string,',
  '"difficulty":1-$articleAiDifficultyMax,',
  '"cefrLevel":"A1"|"A2"|"B1"|"B2"|"C1"|"C2"|null,',
  '"frequency":"VERY_COMMON"|"COMMON"|"NORMAL"|"RARE"|null}],',
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
