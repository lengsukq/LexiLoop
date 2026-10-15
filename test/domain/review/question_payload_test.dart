/// 题目载荷构造的测试。
///
/// 这里能写出确定性断言，靠的是 [shuffleWith] 与 [buildLetterTiles] 的
/// 随机源注入：旧版直接调 `Math.random()`，同样的用例只能断言
/// 「结果在集合内」，永远测不出「打乱后恰好等于原词」这类边界。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

void main() {
  group('shuffleWith', () {
    test('固定随机序列下结果确定，元素集合不变，入参不被修改', () {
      final input = <String>['a', 'b', 'c', 'd'];
      final shuffled = shuffleWith(input, _sequence(<double>[0, 0, 0]));

      expect(shuffled, <String>['b', 'c', 'd', 'a']);
      expect(shuffled.toSet(), input.toSet());
      expect(input, <String>['a', 'b', 'c', 'd'], reason: '入参必须原样保留');
      expect(
        shuffleWith(input, _sequence(<double>[0, 0, 0])),
        shuffled,
        reason: '同一随机序列必须得到同一结果，否则测试无从复现',
      );
    });

    test('空列表与单元素列表不抛异常', () {
      expect(shuffleWith(<String>[], _sequence(<double>[0])), isEmpty);
      expect(shuffleWith(<String>['a'], _sequence(<double>[0])), <String>['a']);
    });

    test('随机源越界返回 1.0 时被夹紧而不是抛 RangeError', () {
      expect(
        shuffleWith(<String>['a', 'b', 'c'], _sequence(<double>[1])),
        <String>['a', 'b', 'c'],
        reason: '夹紧到上界等价于「与自身交换」，即保持原顺序',
      );
    });
  });

  group('buildCloze', () {
    test('优先挑出含目标词的例句，而不是第一条例句', () {
      final payload = buildCloze('apple', <ExampleView>[
        const ExampleView(sentence: 'A dog runs fast.'),
        const ExampleView(sentence: 'I eat an apple daily.'),
      ]);

      expect(payload, isNotNull);
      expect(payload!.sentence, 'I eat an apple daily.');
    });

    test('挖空后含占位符且不再含原词，原句与翻译原样保留', () {
      final payload = buildCloze('apple', <ExampleView>[
        const ExampleView(
          sentence: '  I eat an apple.  ',
          translation: '我吃苹果。',
        ),
      ]);

      expect(payload, isNotNull);
      expect(payload!.sentence, 'I eat an apple.');
      expect(payload.blankedSentence, 'I eat an $clozeBlankToken.');
      expect(payload.blankedSentence.toLowerCase(), isNot(contains('apple')));
      expect(payload.translation, '我吃苹果。');
    });

    test('大小写不敏感：句中是 Apple，词条是 apple', () {
      final payload = buildCloze('apple', <ExampleView>[
        const ExampleView(sentence: 'Apple keeps the doctor away.'),
      ]);

      expect(
        payload!.blankedSentence,
        '$clozeBlankToken keeps the doctor away.',
      );
    });

    test('同一句里出现多次时全部挖空', () {
      final payload = buildCloze('cat', <ExampleView>[
        const ExampleView(sentence: 'A cat and a CAT.'),
      ]);

      expect(
        payload!.blankedSentence,
        'A $clozeBlankToken and a '
        '$clozeBlankToken.',
      );
    });

    test('无例句、例句全空时返回 null', () {
      // 模型里 sentence 不可为 null，故「null 例句」在类型层就等价于
      // 空串或纯空白，这里一并覆盖。
      expect(buildCloze('apple', const <ExampleView>[]), isNull);
      expect(
        buildCloze('apple', <ExampleView>[
          const ExampleView(sentence: ''),
          const ExampleView(sentence: '   '),
        ]),
        isNull,
      );
    });

    test('词边界不命中时退回第一条例句并替换首个出现', () {
      // term 是 cat，句中只有 category：`\bcat\b` 一处也不命中，
      // 没有任何候选可挑，于是走 candidates[0] + 字面替换的兜底路径。
      final payload = buildCloze('cat', <ExampleView>[
        const ExampleView(sentence: 'The category is wide.'),
      ]);

      expect(payload!.sentence, 'The category is wide.');
      expect(payload.blankedSentence, 'The ${clozeBlankToken}egory is wide.');
    });

    test('空词条返回 null，而不是把整句插满占位符', () {
      expect(
        buildCloze('   ', <ExampleView>[const ExampleView(sentence: 'A cat.')]),
        isNull,
      );
    });
  });

  group('buildLetterTiles', () {
    test('块数与词长一致，字母多重集一致，id 互不相同', () {
      final tiles = buildLetterTiles(
        'apple',
        random: _sequence(<double>[0.9, 0.1, 0.5, 0.3, 0.7]),
      );

      expect(tiles, hasLength('apple'.length));
      final letters = tiles.map((tile) => tile.value).toList()..sort();
      expect(letters, <String>['a', 'e', 'l', 'p', 'p']);
      expect(tiles.map((tile) => tile.id).toSet(), hasLength(tiles.length));
      expect(
        tiles.where((tile) => tile.value == 'p').map((tile) => tile.id).toSet(),
        hasLength(2),
        reason: '两个 p 必须各有各的 id，否则拖拽时互相顶替',
      );
    });

    test('打乱结果恰好等于原词时，仍返回与原词顺序不同的排列', () {
      // 0.999 让 Fisher–Yates 每一步都与自身交换，即保持原顺序。
      final tiles = buildLetterTiles(
        'apple',
        random: _sequence(<double>[0.999]),
      );

      expect(tiles.map((tile) => tile.value).join(), isNot('apple'));
      final letters = tiles.map((tile) => tile.value).toList()..sort();
      expect(letters, <String>['a', 'e', 'l', 'p', 'p']);
    });

    test('单字符词条不参与「挪首块」修正', () {
      final tiles = buildLetterTiles('a', random: _sequence(<double>[0.999]));

      expect(tiles, hasLength(1));
      expect(tiles.single.value, 'a');
    });
  });

  group('collectDistinct', () {
    test('忽略大小写与首尾空白去重，达到 limit 即停', () {
      final result = collectDistinct(
        <String>['Apple'],
        <String?>[' apple ', 'APPLE', 'banana', 'Banana', 'cherry', 'date'],
        limit: 3,
      );

      expect(result, <String>['Apple', 'banana', 'cherry']);
    });

    test('null 与空白候选被跳过，种子项计入去重集合', () {
      final result = collectDistinct(
        <String>['apple'],
        <String?>[null, '   ', 'Apple', 'pear'],
        limit: 4,
      );

      expect(result, <String>['apple', 'pear']);
    });

    test('不改动种子列表；种子已满时不消费候选', () {
      final seed = <String>['a', 'b'];
      var pulled = 0;
      Iterable<String?> source() sync* {
        for (final value in <String>['c', 'd']) {
          pulled += 1;
          yield value;
        }
      }

      final result = collectDistinct(seed, source(), limit: 2);

      expect(result, <String>['a', 'b']);
      expect(seed, <String>['a', 'b']);
      expect(pulled, 0);
    });

    test('候选串本身被 trim 后进入结果', () {
      final result = collectDistinct(
        <String>['seed'],
        <String?>['  padded  '],
        limit: 2,
      );

      expect(result, <String>['seed', 'padded']);
    });
  });
}

/// 按固定序列循环返回随机数的假随机源。
///
/// 用序列而不是 `Random(seed)`：前者能精确表达「第几步取哪个下标」，
/// 后者要把种子和实现绑死，换实现就得改测试。
double Function() _sequence(List<double> values) {
  var index = 0;
  return () {
    final value = values[index % values.length];
    index += 1;
    return value;
  };
}
