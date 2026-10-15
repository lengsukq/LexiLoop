/// 内容合并与状态判定测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/dictionary/merge.dart';

DictionaryContent content(Map<String, Object?> fields) =>
    normalizeDictionaryContent(fields);

Map<String, Object?> definition(String text, {String language = 'zh'}) =>
    <String, Object?>{
      'language': language,
      'text': text,
      'partOfSpeech': 'n',
      'source': 'test',
    };

Map<String, Object?> example(String sentence, {String? translation}) =>
    <String, Object?>{
      'sentence': sentence,
      'translation': translation,
      'source': 'test',
    };

void main() {
  group('mergeDictionaryContent', () {
    test('相似释义按阈值去重并保留更长的一条', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'definitions': <Object?>[definition('你好')],
        }),
        content(<String, Object?>{
          'definitions': <Object?>[definition('你好。')],
        }),
      ]);
      final definitions = merged.records('definitions');
      expect(definitions, hasLength(1));
      // 去掉标点后字符集完全相同，判为重复；保留文本更长（更详细）的一条。
      expect(definitions.first['text'], '你好。');
    });

    test('不相似的释义全部保留', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'definitions': <Object?>[definition('苹果')],
        }),
        content(<String, Object?>{
          'definitions': <Object?>[definition('香蕉')],
        }),
      ]);
      expect(merged.records('definitions'), hasLength(2));
    });

    test('同语言同词性之外的释义不会被误判为重复', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'definitions': <Object?>[definition('你好')],
        }),
        content(<String, Object?>{
          'definitions': <Object?>[definition('你好', language: 'en')],
        }),
      ]);
      expect(merged.records('definitions'), hasLength(2));
    });

    test('数组字段做并集去重', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'examples': <Object?>[
            example('He said hello.', translation: '他打了招呼。'),
          ],
        }),
        content(<String, Object?>{
          'examples': <Object?>[
            example('He said hello.'),
            example('She waved hello.'),
          ],
        }),
      ]);
      final examples = merged.records('examples');
      expect(examples, hasLength(2));
      // 先出现的条目优先，因此译文保留。
      expect(examples.first['translation'], '他打了招呼。');
    });

    test('标量字段取第一个非空', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'summary': <String, Object?>{'translation': null},
        }),
        content(<String, Object?>{
          'summary': <String, Object?>{'translation': '你好', 'cefrLevel': 'A1'},
        }),
        content(<String, Object?>{
          'summary': <String, Object?>{
            'translation': '您好',
            'frequency': 'COMMON',
          },
        }),
      ]);
      final summary = merged.record('summary');
      expect(summary['translation'], '你好');
      expect(summary['cefrLevel'], 'A1');
      expect(summary['frequency'], 'COMMON');
    });

    test('对象字段内部的数组取并集', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'learning': <String, Object?>{
            'mnemonic': '谐音记忆',
            'commonMistakes': <Object?>['拼写错误'],
          },
        }),
        content(<String, Object?>{
          'learning': <String, Object?>{
            'mnemonic': null,
            'pronunciationTip': '重音在后',
            'commonMistakes': <Object?>['拼写错误', '时态错误'],
          },
        }),
      ]);
      final learning = merged.record('learning');
      expect(learning['mnemonic'], '谐音记忆');
      expect(learning['pronunciationTip'], '重音在后');
      expect(learning['commonMistakes'], <String>['拼写错误', '时态错误']);
    });

    test('sentenceAnalysis 的 keyExpressions 按 expression 去重', () {
      final merged = mergeDictionaryContent(<DictionaryContent>[
        content(<String, Object?>{
          'sentenceAnalysis': <String, Object?>{
            'keyExpressions': <Object?>[
              <String, Object?>{'expression': 'take care of', 'meaning': '照顾'},
            ],
          },
        }),
        content(<String, Object?>{
          'sentenceAnalysis': <String, Object?>{
            'keyExpressions': <Object?>[
              <String, Object?>{'expression': 'Take Care Of', 'meaning': '照料'},
              <String, Object?>{'expression': 'look after', 'meaning': '照看'},
            ],
          },
        }),
      ]);
      final expressions = merged.records('keyExpressions');
      expect(expressions, hasLength(2));
      expect(expressions.first['meaning'], '照顾');
    });

    test('空输入返回空内容', () {
      final merged = mergeDictionaryContent(<DictionaryContent?>[]);
      expect(merged.records('definitions'), isEmpty);
      expect(merged.record('summary')['translation'], isNull);
    });
  });

  group('preserveUserContent', () {
    test('用户编辑的释义与手工例句在强制覆盖后仍然保留', () {
      final existing = content(<String, Object?>{
        'definitions': <Object?>[
          <String, Object?>{
            'language': 'zh',
            'text': '我自己写的释义',
            'isUserEdited': true,
          },
          definition('词典释义'),
        ],
        'examples': <Object?>[
          <String, Object?>{'sentence': 'My own example.', 'isUserAdded': true},
          example('A dictionary example.'),
        ],
      });
      final refreshed = content(<String, Object?>{
        'definitions': <Object?>[definition('新抓取的释义')],
      });
      final merged = preserveUserContent(existing, refreshed);
      final texts = merged
          .records('definitions')
          .map((item) => item['text'])
          .toList();
      expect(texts, contains('我自己写的释义'));
      expect(texts, contains('新抓取的释义'));
      expect(texts, isNot(contains('词典释义')));
      final sentences = merged
          .records('examples')
          .map((item) => item['sentence'])
          .toList();
      expect(sentences, <String>['My own example.']);
    });
  });

  group('contentStatus', () {
    test('单词：没有释义为 FAILED，有释义无例句为 PARTIAL，都有为 READY', () {
      expect(
        contentStatus(content(<String, Object?>{}), LexicalContentType.word),
        InitializationStatus.failed,
      );
      expect(
        contentStatus(
          content(<String, Object?>{
            'definitions': <Object?>[definition('你好')],
          }),
          LexicalContentType.word,
        ),
        InitializationStatus.partial,
      );
      expect(
        contentStatus(
          content(<String, Object?>{
            'definitions': <Object?>[definition('你好')],
            'examples': <Object?>[example('Hello.')],
          }),
          LexicalContentType.word,
        ),
        InitializationStatus.ready,
      );
    });

    test('句子：有含义无语法解析为 PARTIAL，有译文为 READY', () {
      expect(
        contentStatus(
          content(<String, Object?>{}),
          LexicalContentType.sentence,
        ),
        InitializationStatus.failed,
      );
      expect(
        contentStatus(
          content(<String, Object?>{
            'definitions': <Object?>[definition('我累了')],
          }),
          LexicalContentType.sentence,
        ),
        InitializationStatus.partial,
      );
      expect(
        contentStatus(
          content(<String, Object?>{
            'definitions': <Object?>[definition('我累了')],
            'summary': <String, Object?>{'translation': '我累了'},
          }),
          LexicalContentType.sentence,
        ),
        InitializationStatus.ready,
      );
    });
  });

  group('mergePronunciationField', () {
    test('只补音标时不清空已有音频', () {
      final merged = mergePronunciationField(
        existing: <Map<String, Object?>>[
          <String, Object?>{
            'accent': 'UK',
            'phonetic': null,
            'audioUrl': 'https://x/uk.mp3',
          },
        ],
        incoming: <Map<String, Object?>>[
          <String, Object?>{'accent': 'UK', 'phonetic': 'həˈləʊ'},
        ],
        audio: false,
        force: false,
      );
      expect(merged, hasLength(1));
      expect(merged.first['phonetic'], 'həˈləʊ');
      expect(merged.first['audioUrl'], 'https://x/uk.mp3');
    });

    test('已有音标时非强制模式不覆盖', () {
      final merged = mergePronunciationField(
        existing: <Map<String, Object?>>[
          <String, Object?>{'accent': 'US', 'phonetic': 'həˈloʊ'},
        ],
        incoming: <Map<String, Object?>>[
          <String, Object?>{'accent': 'US', 'phonetic': 'həˈləʊ'},
        ],
        audio: false,
        force: false,
      );
      expect(merged.first['phonetic'], 'həˈloʊ');
    });
  });
}
