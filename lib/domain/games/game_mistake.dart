/// 结算页的失误词条。
///
/// 对应旧版 `components/game-summary.tsx` 的 `SummaryItem` 与
/// `components/game-mistake-flashcards.tsx` 的错词列表。
library;

import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';

/// 本轮失误的词条。
///
/// **为什么不是一行字符串**：旧版 `SummaryItem` 带着 `wordId`，点开才能取
/// 词条详情；把词条压成 `"term · definition"` 一行文本，跳转所需的 ID
/// 就丢了——结算页于是只剩「看得到、点不动」的错词列表。
class GameMistake {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.term,
    required this.definition,
  });

  /// 词条 ID（「看词条详情」的跳转参数）。
  final int wordId;

  /// 英文词条。
  final String term;

  /// 中文释义。
  final String definition;
}

/// 从逐题结果折叠出失误词条（顺序与题目一致）。
///
/// 「失误」= 不是一次答对：纠正完成（`recovered`）与未完成（`missed`）都算，
/// 与旧版 `games/page.tsx` 的 `summaryItems` 一致——它把 `recovered` 与
/// `missed` 都列进结算清单，只有 `correct` 被略过。
List<GameMistake> gameMistakesFor({
  required List<GameQuestion> questions,
  required List<GameOutcome> outcomes,
}) {
  final result = <GameMistake>[];
  for (var index = 0; index < questions.length; index += 1) {
    if (index >= outcomes.length) break;
    if (outcomes[index] == GameOutcome.firstTry) continue;
    final question = questions[index];
    result.add(
      GameMistake(
        wordId: question.wordId,
        term: question.word.term,
        definition: question.word.definition,
      ),
    );
  }
  return result;
}
