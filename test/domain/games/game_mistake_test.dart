/// 结算页失误词条的折叠规则测试。
///
/// 旧版 `game-summary.tsx` 的 `summaryItems` 把 `recovered` 与 `missed` 都列进
/// 结算清单，只有 `correct` 被略过；这里把这个筛选规则钉住，
/// 并确保每个错词都带 `wordId`（「看词条详情」的跳转参数）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mistake.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';

GameQuestion question({
  required int itemId,
  required String term,
  required String definition,
}) {
  return GameQuestion(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(term: term, definition: definition),
    choices: const GameChoices(options: <String>['a', 'b']),
    priority: GamePriority.normal,
  );
}

void main() {
  final questions = <GameQuestion>[
    question(itemId: 1, term: 'cat', definition: '猫'),
    question(itemId: 2, term: 'dog', definition: '狗'),
    question(itemId: 3, term: 'pig', definition: '猪'),
  ];

  test('一次答对不进失误列表，纠正完成与未完成都进', () {
    final mistakes = gameMistakesFor(
      questions: questions,
      outcomes: const <GameOutcome>[
        GameOutcome.firstTry,
        GameOutcome.recovered,
        GameOutcome.missed,
      ],
    );
    expect(mistakes.map((item) => item.term), <String>['dog', 'pig']);
    expect(mistakes.map((item) => item.wordId), <int>[2, 3]);
    expect(mistakes.first.definition, '狗');
  });

  test('全部一次答对时没有失误词条', () {
    final mistakes = gameMistakesFor(
      questions: questions,
      outcomes: const <GameOutcome>[
        GameOutcome.firstTry,
        GameOutcome.firstTry,
        GameOutcome.firstTry,
      ],
    );
    expect(mistakes, isEmpty);
  });

  test('逐题结果比题目少时不会越界', () {
    final mistakes = gameMistakesFor(
      questions: questions,
      outcomes: const <GameOutcome>[GameOutcome.missed],
    );
    expect(mistakes.length, 1);
    expect(mistakes.single.term, 'cat');
  });
}
