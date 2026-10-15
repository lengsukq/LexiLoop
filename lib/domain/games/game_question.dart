/// 题目的构造：选项池、字母拼图块、作答拼接。
///
/// 对应旧版 `modules/games/service.ts` 的 `createGameItems`、
/// `createLetterTiles` 与 `modules/practice/random.ts` 的 `createChoicePool`。
///
/// **与旧版的差异**：旧版的干扰项从「本次抽中的候选」里取，候选不足 4 个时
/// 选项会少于 4 个（旧版只在开局时保证候选 ≥ 4，没有兜底）；这里把选项池
/// 交给调用方传入，服务层负责把池子填满，领域层只负责去重、打乱与截断。
library;

import 'package:lexiloop/domain/games/game_constants.dart';
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
  });

  /// 选项文本（已打乱，含正确项）。
  final List<String> options;

  /// 选项文本 → 中文释义（仅听音选词类题目需要）。
  final Map<String, String> definitions;

  /// 该题是否可用于作答（选项不足时判为不可用，界面据此提示）。
  bool get isUsable => options.length >= gameMinimumChoiceCount;
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
  /// 中译英类题目选英文词条，英译中类题目选中文释义——由 [choices] 的
  /// 构造方式决定，因此这里只需知道「正确项是否在选项里」。
  String get answer => word.term;
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
