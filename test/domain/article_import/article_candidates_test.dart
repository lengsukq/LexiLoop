/// 候选合并、推荐与预览合并的单元测试。
///
/// 钉住的性质：复合键（内容类型 + 归一化词形）、去重与计数相加、
/// KNOWN 优先、推荐词上限与「有 AI 理由优先」、短语/句子默认全选、
/// `aiError` 按预览令牌去重并按批次计数、预览合并的统计口径。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_candidates.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';

ArticleCandidate candidate({
  String term = 'alpha',
  String? normalizedTerm,
  int occurrences = 1,
  ArticleCandidateStatus status = ArticleCandidateStatus.candidate,
  LexicalContentType entryType = LexicalContentType.word,
  String? sourceSentence,
  String? aiReason,
  int? difficulty,
  String? cefrLevel,
  String? frequency,
  ArticleAiCard? aiCard,
}) => ArticleCandidate(
  term: term,
  normalizedTerm: normalizedTerm ?? term.toLowerCase(),
  occurrences: occurrences,
  status: status,
  entryType: entryType,
  sourceSentence: sourceSentence,
  aiReason: aiReason,
  difficulty: difficulty,
  cefrLevel: cefrLevel,
  frequency: frequency,
  aiCard: aiCard,
);

ArticleImportPreview preview({
  String token = 'preview-token',
  List<ArticleCandidate> candidates = const <ArticleCandidate>[],
  List<String> recommendedTerms = const <String>[],
  List<String> recommendedKeys = const <String>[],
  bool aiApplied = false,
  String? aiError,
  int wordCount = 40,
  int charCount = 400,
  int knownCount = 0,
}) => ArticleImportPreview(
  previewToken: token,
  filename: 'p-$token',
  sourceLanguage: 'en',
  targetLanguage: 'zh-CN',
  articleStats: ArticleStats(
    charCount: charCount,
    wordCount: wordCount,
    uniqueCount: candidates.length,
    knownCount: knownCount,
    unknownCount: candidates.length - knownCount,
    phraseCount: 0,
    sentenceCount: 0,
  ),
  candidates: candidates,
  recommendedTerms: recommendedTerms,
  recommendedKeys: recommendedKeys,
  aiApplied: aiApplied,
  aiError: aiError,
  totalCandidates: candidates.length,
  knownCount: knownCount,
  expiresAt: 1,
);

void main() {
  group('候选键', () {
    test('带内容类型前缀，避免单词与短语互相覆盖', () {
      expect(
        articleCandidateKey(LexicalContentType.word, 'take off'),
        'WORD\u0000take off',
      );
      expect(
        articleCandidateKey(LexicalContentType.phrase, 'take off'),
        'PHRASE\u0000take off',
      );
    });

    test('归一化为 NFKC + 小写，但不压缩空白', () {
      expect(
        articleCandidateKey(LexicalContentType.word, 'Ａpple'),
        'WORD\u0000apple',
      );
      expect(
        articleCandidateKey(LexicalContentType.word, 'a  b'),
        'WORD\u0000a  b',
      );
    });
  });

  group('合并候选', () {
    test('同键候选出现次数相加', () {
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(occurrences: 2),
        candidate(occurrences: 3),
      ]);
      expect(merged.single.occurrences, 5);
    });

    test('不同内容类型不合并', () {
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(),
        candidate(entryType: LexicalContentType.phrase),
      ]);
      expect(merged.length, 2);
    });

    test('难度更大的一方提供难度、CEFR 与词频', () {
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(difficulty: 2, cefrLevel: 'B1', frequency: 'COMMON'),
        candidate(difficulty: 4, cefrLevel: 'C1', frequency: 'RARE'),
      ]).single;
      expect(merged.difficulty, 4);
      expect(merged.cefrLevel, 'C1');
      expect(merged.frequency, 'RARE');
    });

    test('难度相等时保留先出现的一方的元数据', () {
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(difficulty: 3, cefrLevel: 'B2'),
        candidate(difficulty: 3, cefrLevel: 'C2'),
      ]).single;
      expect(merged.cefrLevel, 'B2');
    });

    test('任一方已掌握则结果为已掌握', () {
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(status: ArticleCandidateStatus.known),
        candidate(),
      ]).single;
      expect(merged.status, ArticleCandidateStatus.known);
    });

    test('理由、出处句、AI 卡片只在原值为空时被填充', () {
      const card = ArticleAiCard(
        literalTranslation: '字面',
        freeTranslation: '意译',
      );
      final merged = mergeArticleCandidates(<ArticleCandidate>[
        candidate(aiReason: '原有理由', sourceSentence: '原有出处'),
        candidate(aiReason: '新理由', sourceSentence: '新出处', aiCard: card),
      ]).single;
      expect(merged.aiReason, '原有理由');
      expect(merged.sourceSentence, '原有出处');
      expect(merged.aiCard, card);
    });
  });

  group('推荐词', () {
    test('有 AI 理由的候选优先，且不设上限', () {
      final merged = <ArticleCandidate>[
        for (
          var index = 0;
          index < articleDefaultRecommendedLimit + 5;
          index += 1
        )
          candidate(term: 'w$index', aiReason: '值得学'),
      ];
      final terms = fallbackRecommendedTerms(merged);
      expect(terms.length, merged.length);
    });

    test('没有 AI 理由时取前若干个待学单词', () {
      final merged = <ArticleCandidate>[
        for (
          var index = 0;
          index < articleDefaultRecommendedLimit + 5;
          index += 1
        )
          candidate(term: 'w$index'),
      ];
      expect(
        fallbackRecommendedTerms(merged).length,
        articleDefaultRecommendedLimit,
      );
    });

    test('已掌握的词与短语 / 句子不进入回退推荐', () {
      final merged = <ArticleCandidate>[
        candidate(status: ArticleCandidateStatus.known),
        candidate(entryType: LexicalContentType.phrase),
        candidate(entryType: LexicalContentType.sentence),
      ];
      expect(fallbackRecommendedTerms(merged), isEmpty);
    });

    test('推荐键：单词按推荐词缀，短语与句子全选', () {
      final merged = <ArticleCandidate>[
        candidate(term: 'apple'),
        candidate(term: 'banana'),
        candidate(term: 'take off', entryType: LexicalContentType.phrase),
        candidate(term: 'It works.', entryType: LexicalContentType.sentence),
        candidate(term: 'known', status: ArticleCandidateStatus.known),
      ];
      final keys = recommendedCandidateKeys(merged, <String>['apple']);
      expect(keys, <String>[
        'WORD\u0000apple',
        'PHRASE\u0000take off',
        'SENTENCE\u0000it works.',
      ]);
    });
  });

  group('初次勾选', () {
    test('有 recommendedKeys 时直接小写采用', () {
      final keys = initialSelectionKeys(
        preview(recommendedKeys: <String>['WORD\u0000Apple']),
      );
      expect(keys, <String>{'word\u0000apple'});
    });

    test('没有 recommendedKeys 时按推荐词缀现算', () {
      final keys = initialSelectionKeys(
        preview(
          candidates: <ArticleCandidate>[
            candidate(term: 'apple'),
            candidate(term: 'banana'),
          ],
          recommendedTerms: <String>['apple'],
        ),
      );
      expect(keys, <String>{'word\u0000apple'});
    });
  });

  group('AI 失败原因合并', () {
    test('同一预览令牌的同一条文案只算一次', () {
      final merged = mergeAiErrors(<ArticleImportPreview>[
        preview(token: 't1', aiError: 'AI 未启用'),
        preview(token: 't1', aiError: 'AI 未启用'),
      ]);
      expect(merged, 'AI 未启用');
    });

    test('不同批次的相同文案合并计数', () {
      final merged = mergeAiErrors(<ArticleImportPreview>[
        preview(token: 't1', aiError: 'AI 未启用'),
        preview(token: 't2', aiError: 'AI 未启用'),
        preview(token: 't3', aiError: '格式无效'),
      ]);
      expect(merged, 'AI 未启用（2 批）；格式无效');
    });

    test('全为空时返回 null', () {
      expect(
        mergeAiErrors(<ArticleImportPreview>[
          preview(token: 't1'),
          preview(token: 't2', aiError: '   '),
        ]),
        isNull,
      );
    });
  });

  group('合并预览', () {
    test('空列表返回 null，单元素原样返回', () {
      expect(mergeArticlePreviews(<ArticleImportPreview>[]), isNull);
      final single = preview();
      expect(
        mergeArticlePreviews(<ArticleImportPreview>[single]),
        same(single),
      );
    });

    test('按预览令牌去重后再合并候选与统计', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(
          token: 't1',
          candidates: <ArticleCandidate>[candidate(occurrences: 2)],
          wordCount: 10,
          charCount: 100,
        ),
        preview(
          token: 't1',
          candidates: <ArticleCandidate>[candidate(occurrences: 2)],
          wordCount: 10,
          charCount: 100,
        ),
        preview(
          token: 't2',
          candidates: <ArticleCandidate>[candidate(occurrences: 3)],
          wordCount: 20,
          charCount: 200,
        ),
      ])!;
      expect(merged.candidates.single.occurrences, 5);
      expect(merged.articleStats.wordCount, 30);
      expect(merged.articleStats.charCount, 300);
    });

    test('任一预览启用过 AI 即视为已筛选', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(token: 't1'),
        preview(token: 't2', aiApplied: true),
      ])!;
      expect(merged.aiApplied, isTrue);
    });

    test('AI 理由或卡片存在时也视为已筛选', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(
          token: 't1',
          candidates: <ArticleCandidate>[candidate(aiReason: '值得学')],
        ),
        preview(
          token: 't2',
          candidates: <ArticleCandidate>[candidate(term: 'other')],
        ),
      ])!;
      expect(merged.aiApplied, isTrue);
    });

    test('词数缺失时用去重词数乘以估算倍数', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(
          token: 't1',
          candidates: <ArticleCandidate>[candidate()],
          wordCount: 0,
        ),
        preview(
          token: 't2',
          candidates: <ArticleCandidate>[candidate(term: 'other')],
          wordCount: 0,
        ),
      ])!;
      expect(merged.articleStats.uniqueCount, 2);
      expect(merged.articleStats.wordCount, 2 * 2);
    });

    test('AI 失败原因随合并结果带出', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(token: 't1', aiError: 'AI 未启用'),
        preview(token: 't2', aiError: 'AI 未启用'),
      ])!;
      expect(merged.aiError, 'AI 未启用（2 批）');
    });

    test('推荐键随合并结果重算', () {
      final merged = mergeArticlePreviews(<ArticleImportPreview>[
        preview(
          token: 't1',
          candidates: <ArticleCandidate>[candidate(term: 'apple')],
        ),
        preview(
          token: 't2',
          candidates: <ArticleCandidate>[
            candidate(term: 'take off', entryType: LexicalContentType.phrase),
          ],
        ),
      ])!;
      expect(merged.recommendedKeys, contains('PHRASE\u0000take off'));
    });
  });
}
