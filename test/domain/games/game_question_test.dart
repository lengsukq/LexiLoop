/// 题目构造的单元测试（选项池、字母块、作答比对）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

import 'random_source.dart';

void main() {
  group('createChoicePool', () {
    test('选项数量达到要求且包含正确项', () {
      final choices = createChoicePool(
        correct: 'cat',
        pool: <String>['cat', 'dog', 'pig', 'cow', 'fox'],
        size: gameChoiceCount,
        random: constantRandom(),
      );
      expect(choices.length, gameChoiceCount);
      expect(choices, contains('cat'));
    });

    test('候选不足时不会凭空造选项', () {
      final choices = createChoicePool(
        correct: 'cat',
        pool: <String>['cat', 'dog'],
        size: gameChoiceCount,
        random: constantRandom(),
      );
      expect(choices.toSet(), <String>{'cat', 'dog'});
    });

    test('按大小写不敏感去重，且忽略空白项', () {
      final choices = createChoicePool(
        correct: 'Cat',
        pool: <String>['  cat ', 'CAT', '', 'dog'],
        size: gameChoiceCount,
        random: constantRandom(),
      );
      expect(choices.length, 2);
      expect(
        choices.where((item) => item.trim().toLowerCase() == 'cat').length,
        1,
      );
    });

    test('随机源决定顺序：全 0 与全 0.99 得到的顺序不同', () {
      final a = createChoicePool(
        correct: 'cat',
        pool: <String>['dog', 'pig', 'cow'],
        size: gameChoiceCount,
        random: constantRandom(),
      );
      final b = createChoicePool(
        correct: 'cat',
        pool: <String>['dog', 'pig', 'cow'],
        size: gameChoiceCount,
        random: constantRandom(0.99),
      );
      expect(a.toSet(), b.toSet());
      expect(a, isNot(equals(b)));
    });
  });

  group('字母块', () {
    test('同一字母的不同位置有不同 id，按 id 顺序可拼回原词', () {
      final tiles = buildLetterTiles('apple', random: constantRandom());
      expect(tiles.length, 5);
      expect(tiles.map((tile) => tile.id).toSet().length, 5);
      final ordered = <LetterTile>[...tiles]
        ..sort((left, right) => left.id.compareTo(right.id));
      expect(
        joinLetters(tiles, ordered.map((tile) => tile.id).toList()),
        'apple',
      );
    });

    test('打乱后恰好等于原词时会被错开', () {
      final tiles = buildLetterTiles('ab', random: constantRandom());
      final joined = tiles.map((tile) => tile.value).join();
      expect(joined.toLowerCase(), isNot('ab'));
    });
  });

  group('作答比对', () {
    test('忽略大小写与首尾空白', () {
      expect(lettersMatchTerm(answer: ' Cat ', term: 'cat'), isTrue);
      expect(lettersMatchTerm(answer: 'cat', term: 'dog'), isFalse);
    });
  });

  group('选项可用性', () {
    test('选项少于 2 个时判为不可用', () {
      expect(const GameChoices(options: <String>['a']).isUsable, isFalse);
      expect(const GameChoices(options: <String>['a', 'b']).isUsable, isTrue);
    });
  });
}
