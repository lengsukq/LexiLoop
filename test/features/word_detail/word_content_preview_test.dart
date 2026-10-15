/// 有道预览内容组件的测试。
///
/// 这一层是纯展示：钉住「空分区整块不出现」与「词形类型的中文映射」，
/// 因为旧版把 `formLabel` 的映射写在组件文件里、只被弹窗间接覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/dialogs/word_content_preview.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';

import '../../support/app_harness.dart';

void main() {
  Future<void> pumpPreview(
    WidgetTester tester,
    DictionaryContent content,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithAppTheme(Scaffold(body: WordContentPreview(content: content))),
    );
    await tester.pumpAndSettle();
  }

  test('词形类型映射与旧版逐条一致', () {
    expect(formLabel('PLURAL'), '复数');
    expect(formLabel('THIRD_PERSON'), '三单');
    expect(formLabel('PRESENT_PARTICIPLE'), '现在分词');
    expect(formLabel('PAST'), '过去式');
    expect(formLabel('PAST_PARTICIPLE'), '过去分词');
    expect(formLabel('COMPARATIVE'), '比较级');
    expect(formLabel('SUPERLATIVE'), '最高级');
    expect(formLabel('LEMMA'), 'LEMMA', reason: '未收录的类型回显原值而不是空白');
  });

  test('关联词关系映射与旧版逐条一致', () {
    expect(relationLabel(RelationType.synonym), '近义词');
    expect(relationLabel(RelationType.antonym), '反义词');
    expect(relationLabel(RelationType.wordFamily), '同根词 / 词族');
    expect(relationLabel(RelationType.confusedWith), '易混词');
  });

  testWidgets('六个分区按内容出现，空分区整块不显示', (tester) async {
    await pumpPreview(
      tester,
      const DictionaryContent(<String, Object?>{
        'summary': <String, Object?>{'translation': '苹果'},
        'pronunciations': <Object?>[
          <String, Object?>{'accent': 'UK', 'phonetic': 'ˈæpl'},
        ],
        'definitions': <Object?>[
          <String, Object?>{'text': '苹果', 'partOfSpeech': 'n.'},
        ],
        'examples': <Object?>[
          <String, Object?>{'sentence': 'An apple.', 'translation': '一个苹果。'},
        ],
        'phrases': <Object?>[
          <String, Object?>{'phrase': 'apple pie', 'translation': '苹果派'},
        ],
        'forms': <Object?>[
          <String, Object?>{'type': 'PLURAL', 'value': 'apples'},
        ],
      }),
    );

    expect(find.text('翻译摘要'), findsOneWidget);
    expect(find.text('苹果'), findsWidgets);
    expect(find.text('英 /ˈæpl/'), findsOneWidget);
    expect(find.text('释义'), findsOneWidget);
    expect(find.text('n.'), findsOneWidget);
    expect(find.text('例句'), findsOneWidget);
    expect(find.text('An apple.'), findsOneWidget);
    expect(find.text('一个苹果。'), findsOneWidget);
    expect(find.text('短语搭配'), findsOneWidget);
    expect(find.text('apple pie · 苹果派'), findsOneWidget);
    expect(find.text('词形变化'), findsOneWidget);
    expect(find.text('复数: apples'), findsOneWidget);
  });

  testWidgets('内容为空时不渲染任何分区', (tester) async {
    await pumpPreview(tester, emptyDictionaryContent());

    expect(find.text('翻译摘要'), findsNothing);
    expect(find.text('释义'), findsNothing);
    expect(find.text('例句'), findsNothing);
    expect(find.text('短语搭配'), findsNothing);
    expect(find.text('词形变化'), findsNothing);
  });
}
