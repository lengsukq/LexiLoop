/// AI 选词 Schema 与容错解析的单元测试。
///
/// 钉住的性质：结构化输出 Schema 与旧版 zod 上限逐条对应（含 strict 模式
/// 「required 必须覆盖全部 properties」的不变量）、宽容解析的截断 / 默认值 /
/// 枚举过滤、以及「一项都解析不出来时返回 null」这条回退信号。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_ai_schema.dart';

/// 递归取出 Schema 里全部「对象」节点的 required 与 properties 键。
List<Map<String, Object?>> _objectSchemas(Object? node) {
  final found = <Map<String, Object?>>[];
  if (node is List) {
    for (final item in node) {
      found.addAll(_objectSchemas(item));
    }
    return found;
  }
  if (node is! Map) return found;
  final properties = node['properties'];
  final required = node['required'];
  if (properties is Map && required is List) {
    found.add(<String, Object?>{
      'properties': properties.keys.map((key) => '$key').toSet(),
      'required': required.map((key) => '$key').toSet(),
    });
    for (final value in properties.values) {
      found.addAll(_objectSchemas(value));
    }
  }
  for (final value in node.values) {
    if (value is Map || value is List) found.addAll(_objectSchemas(value));
  }
  return found;
}

void main() {
  group('Schema', () {
    test('顶层要求三个数组', () {
      final schema = articleAiSelectionJsonSchema;
      expect(schema['required'], <String>['words', 'phrases', 'sentences']);
      expect(schema['additionalProperties'], isFalse);
    });

    test('各数组上限与常量一致', () {
      final properties =
          articleAiSelectionJsonSchema['properties']! as Map<String, Object?>;
      expect(
        (properties['words']! as Map<String, Object?>)['maxItems'],
        articleAiWordsMaxItems,
      );
      expect(
        (properties['phrases']! as Map<String, Object?>)['maxItems'],
        articlePhraseLimit,
      );
      expect(
        (properties['sentences']! as Map<String, Object?>)['maxItems'],
        articleSentenceLimit,
      );
    });

    test('strict 模式：每个对象的 required 覆盖全部 properties', () {
      for (final node in _objectSchemas(articleAiSelectionJsonSchema)) {
        expect(
          node['required'],
          node['properties'],
          reason: 'OpenAI strict 模式要求 properties 里的每个键都在 required 中',
        );
      }
    });

    test('难度区间引用常量', () {
      final properties =
          articleAiSelectionJsonSchema['properties']! as Map<String, Object?>;
      final words = properties['words']! as Map<String, Object?>;
      final items = words['items']! as Map<String, Object?>;
      final wordProperties = items['properties']! as Map<String, Object?>;
      final difficulty = wordProperties['difficulty']! as Map<String, Object?>;
      expect(difficulty['minimum'], 1);
      expect(difficulty['maximum'], articleAiDifficultyMax);
    });
  });

  group('容错解析', () {
    test('非对象或空内容一律返回 null（回退信号）', () {
      expect(normalizeAiSelectionResponse(null), isNull);
      expect(normalizeAiSelectionResponse('text'), isNull);
      expect(normalizeAiSelectionResponse(<Object?>[]), isNull);
      expect(normalizeAiSelectionResponse(<String, Object?>{}), isNull);
      expect(
        normalizeAiSelectionResponse(<String, Object?>{
          'words': <Object?>[],
          'phrases': <Object?>[],
          'sentences': <Object?>[],
        }),
        isNull,
      );
    });

    test('解析单词：理由缺失时用默认理由，难度越界夹取', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'words': <Object?>[
          <String, Object?>{'term': 'apple'},
          <String, Object?>{'term': 'banana', 'reason': '常用', 'difficulty': 9},
          <String, Object?>{'term': 'cherry', 'difficulty': 'abc'},
        ],
      })!;
      expect(result.words.length, 3);
      expect(result.words[0].reason, articleDefaultReason);
      expect(result.words[0].difficulty, articleAiDifficultyFallback);
      expect(result.words[1].difficulty, articleAiDifficultyMax);
      expect(result.words[2].difficulty, articleAiDifficultyFallback);
    });

    test('CEFR 与词频大写化，非法取值丢弃', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'words': <Object?>[
          <String, Object?>{
            'term': 'apple',
            'cefrLevel': 'b2',
            'frequency': 'rare',
          },
          <String, Object?>{
            'term': 'banana',
            'cefrLevel': 'Z9',
            'frequency': 'OFTEN',
          },
        ],
      })!;
      expect(result.words[0].cefrLevel, 'B2');
      expect(result.words[0].frequency, 'RARE');
      expect(result.words[1].cefrLevel, isNull);
      expect(result.words[1].frequency, isNull);
    });

    test('超长字段被截断而不是整条丢弃', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'words': <Object?>[
          <String, Object?>{
            'term': 'a' * (articleAiTermMaxChars + 10),
            'reason': 'b' * (articleAiReasonMaxChars + 10),
          },
        ],
      })!;
      expect(result.words.single.term.length, articleAiTermMaxChars);
      expect(result.words.single.reason.length, articleAiReasonMaxChars);
    });

    test('支持旧版的 selected 别名', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'selected': <Object?>[
          <String, Object?>{'term': 'apple'},
        ],
      })!;
      expect(result.words.single.term, 'apple');
    });

    test('键名大小写不敏感', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'Words': <Object?>[
          <String, Object?>{'TERM': 'apple'},
        ],
      });
      // 列表键大小写不敏感；元素内的键沿用旧版行为（只认小写）。
      expect(result, isNull);
    });

    test('短语缺直译或意译时被丢弃', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'phrases': <Object?>[
          <String, Object?>{
            'term': 'take off',
            'literalTranslation': '脱下',
            'freeTranslation': '起飞',
          },
          <String, Object?>{'term': 'no translation'},
        ],
      })!;
      expect(result.phrases.single.term, 'take off');
    });

    test('重点词汇过滤空条目并截到上限', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'phrases': <Object?>[
          <String, Object?>{
            'term': 'take off',
            'literalTranslation': '脱下',
            'freeTranslation': '起飞',
            'keyVocab': <Object?>[
              <String, Object?>{'term': 'take', 'meaning': '拿'},
              <String, Object?>{'term': 'off'},
              <String, Object?>{'meaning': '离开'},
              for (
                var index = 0;
                index < articleAiPhraseKeyVocabMaxItems + 3;
                index += 1
              )
                <String, Object?>{
                  'term': 'w$index',
                  'pos': 'v.',
                  'meaning': '释义$index',
                },
            ],
          },
        ],
      })!;
      expect(
        result.phrases.single.keyVocab.length,
        articleAiPhraseKeyVocabMaxItems,
      );
      expect(result.phrases.single.keyVocab.first.term, 'take');
    });

    test('语法要点截到上限，句型超长截断', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'phrases': <Object?>[
          <String, Object?>{
            'term': 'take off',
            'literalTranslation': '脱下',
            'freeTranslation': '起飞',
            'grammar': <String, Object?>{
              'pattern': 'p' * (articleAiGrammarPatternMaxChars + 5),
              'notes': <Object?>[
                for (
                  var index = 0;
                  index < articleAiGrammarNotesMaxItems + 2;
                  index += 1
                )
                  'note$index',
              ],
            },
          },
        ],
      })!;
      final phrase = result.phrases.single;
      expect(phrase.grammarPattern!.length, articleAiGrammarPatternMaxChars);
      expect(phrase.grammarNotes.length, articleAiGrammarNotesMaxItems);
    });

    test('句子缺原文时被丢弃', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'sentences': <Object?>[
          <String, Object?>{
            'literalTranslation': '直译',
            'freeTranslation': '意译',
          },
          <String, Object?>{
            'sentence': 'It works.',
            'literalTranslation': '它工作。',
            'freeTranslation': '它行得通。',
          },
        ],
      })!;
      expect(result.sentences.single.sentence, 'It works.');
    });

    test('数组上限与常量一致', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'words': <Object?>[
          for (var index = 0; index < articleAiWordsMaxItems + 5; index += 1)
            <String, Object?>{'term': 'w$index'},
        ],
      })!;
      expect(result.words.length, articleAiWordsMaxItems);
    });

    test('同时解析出单词、短语与句子', () {
      final result = normalizeAiSelectionResponse(<String, Object?>{
        'words': <Object?>[
          <String, Object?>{'term': 'apple'},
        ],
        'phrases': <Object?>[
          <String, Object?>{
            'term': 'take off',
            'literalTranslation': '脱下',
            'freeTranslation': '起飞',
          },
        ],
        'sentences': <Object?>[
          <String, Object?>{
            'sentence': 'It works.',
            'literalTranslation': '它工作。',
            'freeTranslation': '它行得通。',
          },
        ],
      })!;
      expect(result.applied, isTrue);
      expect(result.hasContent, isTrue);
      expect(result.words, hasLength(1));
      expect(result.phrases, hasLength(1));
      expect(result.sentences, hasLength(1));
    });
  });
}
