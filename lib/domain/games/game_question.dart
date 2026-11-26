/// 题目的构造：选项池、字母拼图块、作答拼接。
///
/// 对应旧版 `modules/games/service.ts` 的 `createGameItems`、
/// `createLetterTiles` 与 `modules/practice/random.ts` 的 `createChoicePool`。
///
/// **与旧版的差异**：旧版的干扰项从「本次抽中的候选」里取，候选不足 4 个时
/// 选项会少于 4 个（旧版只在开局时保证候选 ≥ 4，没有兜底）；这里把选项池
/// 交给调用方传入，服务层负责把池子填满，领域层只负责去重、打乱与截断。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 一道题的词条侧信息。
class GameWord {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.definition,
    this.letters = const <LetterTile>[],
  });

  /// 英文词条（答案）。
  final String term;

  /// 中文释义（题干）。
  final String definition;

  /// 字母拼图块（仅单词拼图题使用）。
  final List<LetterTile> letters;
}

/// 一道题的选项集合。
class GameChoices {
  /// 以各字段构造。
  const new({
    required this.options,
    this.definitions = const <String, String>{},
    this.correct,
  });

  /// 选项文本（已打乱，含正确项）。
  final List<String> options;

  /// 选项文本 → 中文释义（仅听音选词类题目需要）。
  final Map<String, String> definitions;

  /// 正确选项的文本；`null` 表示正确项就是词形。
  ///
  /// **为什么正确项由出题方写死**：旧版在 `games/page.tsx:217` 现场判题
  /// （`session.mode === "MEANING_BLITZ" ? current.definition : current.term`），
  /// 「哪个模式的正确项是释义」这条规则因此散在界面层，判题代码离不开模式。
  /// 出题时把正确项写进题目后，判题只看 [GameQuestion.answer]，
  /// 听音辨词与词义冲刺因此可以共用同一个状态机。
  final String? correct;

  /// 该题是否可用于作答（选项不足时判为不可用，界面据此提示）。
  bool get isUsable => options.length >= gameMinimumChoiceCount;
}

/// 一局候选池派生出的干扰项来源。
///
/// **为什么要有它**：旧版 `createGameItems`（`games/service.ts`）在函数体里
/// 现算 `terms` 与 `definitions` 两个数组，再用一个三元链决定拿哪个当池子；
/// 这里把「池子怎么来」与「按模式选哪个池子」拆成两步，
/// 加模式时只需要改 [choicesFor] 一处。
class GameChoicePools {
  /// 以各字段构造。
  const new({
    required this.terms,
    required this.definitions,
    required this.termDefinitions,
  });

  /// 本局全部候选的词形。
  final List<String> terms;

  /// 本局全部候选的释义。
  final List<String> definitions;

  /// 词形 → 释义（听音辨词的选项副标题用）。
  final Map<String, String> termDefinitions;

  /// 按模式造一道题的选项集合。
  ///
  /// 与旧版 `createGameItems` 逐条对应：词义冲刺的选项池是**释义**
  /// （正确项也是释义），听音辨词与其余选择题模式的选项池是**词形**；
  /// 单词拼图不用选项，改用字母块。配对与音标各有自己的出题路径
  /// （`matching_service.dart` / `domain/phonetics/selection.dart`），
  /// 不会走到这里，这里给空选项而不是抛错。
  GameChoices choicesFor({
    required GameMode mode,
    required String term,
    required String definition,
    required double Function() random,
  }) {
    return switch (mode) {
      GameMode.wordBuilder ||
      GameMode.match ||
      GameMode.phonetics => const GameChoices(options: <String>[]),
      GameMode.meaningBlitz => GameChoices(
        options: createChoicePool(
          correct: definition,
          pool: definitions,
          size: gameChoiceCount,
          random: random,
        ),
        correct: definition,
      ),
      GameMode.listeningPick => GameChoices(
        options: createChoicePool(
          correct: term,
          pool: terms,
          size: gameChoiceCount,
          random: random,
        ),
        definitions: termDefinitions,
      ),
      GameMode.whackAMole ||
      GameMode.wordStack ||
      GameMode.wordTetris => GameChoices(
        options: createChoicePool(
          correct: term,
          pool: terms,
          size: gameChoiceCount,
          random: random,
        ),
      ),
    };
  }
}

/// 一道完整的游戏题目。
class GameQuestion {
  /// 以各字段构造。
  const new({
    required this.itemId,
    required this.wordId,
    required this.word,
    required this.choices,
    required this.priority,
  });

  /// 会话题目 ID（结算时作为幂等键与题目引用）。
  final int itemId;

  /// 词条 ID。
  final int wordId;

  /// 词条侧信息。
  final GameWord word;

  /// 选项集合。
  final GameChoices choices;

  /// 该词条在候选池里的优先级（界面据此打「重点复习词」标记）。
  final GamePriority priority;

  /// 该题的正确选项文本。
  ///
  /// 中译英类题目选英文词条，英译中类题目选中文释义——由
  /// [GameChoices.correct] 决定（出题时写入），缺省即词形。
  String get answer => choices.correct ?? word.term;
}

/// 从候选池里造一个含正确项、且去重后长度为 [size] 的选项列表。
///
/// 与旧版 `createChoicePool` 一致：先打乱候选、逐个去重、够了就停，
/// 最后再整体打乱一次，保证正确项位置随机。
List<String> createChoicePool({
  required String correct,
  required List<String> pool,
  required int size,
  required double Function() random,
}) {
  final result = <String>[correct];
  final seen = <String>{_identity(correct)};
  for (final candidate in shuffleWith(pool, random)) {
    if (result.length >= size) break;
    final text = candidate.trim();
    if (text.isEmpty) continue;
    if (!seen.add(_identity(text))) continue;
    result.add(text);
  }
  return shuffleWith(result, random);
}

/// 把选中的字母块拼成作答文本。
///
/// [selectedIds] 是字母块 id 的有序集合（点选顺序即拼写顺序）。
String joinLetters(List<LetterTile> letters, List<String> selectedIds) {
  final byId = <String, String>{
    for (final letter in letters) letter.id: letter.value,
  };
  final buffer = StringBuffer();
  for (final id in selectedIds) {
    buffer.write(byId[id] ?? '');
  }
  return buffer.toString();
}

/// 判断作答是否与目标词条一致（忽略大小写与首尾空白）。
bool lettersMatchTerm({required String answer, required String term}) =>
    answer.trim().toLowerCase() == term.trim().toLowerCase();

/// 去重比较用的键。
String _identity(String text) => text.trim().toLowerCase();
