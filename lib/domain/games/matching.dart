/// 限时词汇配对（MATCH）的纯状态机。
///
/// 对应旧版 `app/(main)/match/page.tsx`：
/// 左列是英文词条、右列是中文释义，两列各自独立打乱；
/// 依次点两张牌，同属一个词条即配对成功并消除。
///
/// **判定规则与旧版逐条一致**：
/// - 已消除的牌不可再点；错配闪烁期间整盘锁定；
/// - 同一列内再点一张只切换选择（点同一张则取消选择）；
/// - 跨列且同属一个词条 → 配对成功，连击 +1；
/// - 跨列但不同词条 → 记一次失误，**两张牌都标记为曾失误**
///   （旧版 `recordMistake(selected.itemId, item.itemId)` 就是这个语义），
///   因此这一对即便之后配对成功也只算「纠正完成」而不是「一次配对」；
/// - 全部配对成功 → 本局结束。
///
/// **与旧版的差异**：旧版把「错配闪烁 460ms 后清空」写成 `setTimeout`，
/// 这里改为显式的 [ClearMatchFlash] 动作，让状态机可单测。
library;

import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 牌面的一侧。
enum MatchSide {
  /// 英文词条列。
  word,

  /// 中文释义列。
  definition,
}

/// 一张牌。
class MatchCardRef {
  /// 以各字段构造。
  const new({required this.side, required this.itemId});

  /// 所在列。
  final MatchSide side;

  /// 所属词条的会话题目 ID。
  final int itemId;

  /// 稳定键（`word:12`），用于错配闪烁集合的去重。
  String get key => '${side.name}:$itemId';

  @override
  String toString() => key;
}

/// 两列的展示顺序（存题目下标）。
class MatchDeck {
  /// 以各字段构造。
  const new({required this.words, required this.definitions});

  /// 英文列的顺序。
  final List<int> words;

  /// 释义列的顺序。
  final List<int> definitions;
}

/// 瞬时反馈状态。
class MatchFeedback {
  /// 以各字段构造。
  const new({
    this.selected,
    this.wrongFlash = const <String>{},
    this.sinceLastMatchMs = 0,
  });

  /// 当前选中的牌。
  final MatchCardRef? selected;

  /// 正在闪烁的错配牌的键（[MatchCardRef.key]）。
  final Set<String> wrongFlash;

  /// 距上次成功配对的耗时（作为该对的作答时长）。
  final int sinceLastMatchMs;

  /// 是否处于错配锁定中。
  bool get isLocked => wrongFlash.isNotEmpty;

  /// 复制并覆盖部分字段。
  MatchFeedback copyWith({
    MatchCardRef? selected,
    bool clearSelected = false,
    Set<String>? wrongFlash,
    int? sinceLastMatchMs,
  }) {
    return MatchFeedback(
      selected: clearSelected ? null : (selected ?? this.selected),
      wrongFlash: wrongFlash ?? this.wrongFlash,
      sinceLastMatchMs: sinceLastMatchMs ?? this.sinceLastMatchMs,
    );
  }
}

/// 配对牌面的状态。
class MatchBoardState {
  /// 以各字段构造。
  const new({
    required this.pairs,
    required this.deck,
    required this.core,
    this.feedback = const MatchFeedback(),
    this.matchedItemIds = const <int>{},
  });

  /// 全部词条（作为配对题，`choices` 为空）。
  final List<GameQuestion> pairs;

  /// 两列的展示顺序。
  final MatchDeck deck;

  /// 计分内核。
  final GameCoreState core;

  /// 瞬时反馈。
  final MatchFeedback feedback;

  /// 已配对成功的题目 ID。
  final Set<int> matchedItemIds;

  /// 是否全部配对完成。
  bool get isComplete => matchedItemIds.length >= pairs.length;

  /// 已配对数量。
  int get matchedCount => matchedItemIds.length;

  /// 复制并覆盖部分字段。
  MatchBoardState copyWith({
    GameCoreState? core,
    MatchFeedback? feedback,
    Set<int>? matchedItemIds,
  }) {
    return MatchBoardState(
      pairs: pairs,
      deck: deck,
      core: core ?? this.core,
      feedback: feedback ?? this.feedback,
      matchedItemIds: matchedItemIds ?? this.matchedItemIds,
    );
  }
}

/// 配对的动作。
sealed class MatchAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartMatch extends MatchAction {
  /// 构造。
  const new();
}

/// 时间前进。
final class TickMatch extends MatchAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 点一张牌。
final class TapMatchCard extends MatchAction {
  /// 以列与题目 ID 构造。
  const new({required this.side, required this.itemId});

  /// 所在列。
  final MatchSide side;

  /// 题目 ID。
  final int itemId;
}

/// 清除错配闪烁并解锁牌面。
final class ClearMatchFlash extends MatchAction {
  /// 构造。
  const new();
}

/// 建一局配对（两列各自独立打乱）。
MatchBoardState startMatchingBoard({
  required GamePlan plan,
  required List<GameQuestion> pairs,
  required double Function() random,
}) {
  final order = <int>[
    for (var index = 0; index < pairs.length; index += 1) index,
  ];
  return MatchBoardState(
    pairs: pairs,
    deck: MatchDeck(
      words: shuffleWith(order, random),
      definitions: shuffleWith(order, random),
    ),
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口。
MatchBoardState matchBoardNext(MatchBoardState state, MatchAction action) {
  return switch (action) {
    StartMatch() => state.copyWith(core: state.core.start()),
    TickMatch(:final deltaMs) => _tick(state, deltaMs),
    TapMatchCard(:final side, :final itemId) => _tap(state, side, itemId),
    ClearMatchFlash() => state.copyWith(
      feedback: MatchFeedback(
        sinceLastMatchMs: state.feedback.sinceLastMatchMs,
      ),
    ),
  };
}

MatchBoardState _tick(MatchBoardState state, int deltaMs) {
  if (state.core.isFinished) return state;
  return state.copyWith(
    core: state.core.tick(deltaMs: deltaMs),
    feedback: state.feedback.copyWith(
      sinceLastMatchMs: state.feedback.sinceLastMatchMs + deltaMs,
    ),
  );
}

MatchBoardState _tap(MatchBoardState state, MatchSide side, int itemId) {
  if (!state.core.isPlaying || state.feedback.isLocked) return state;
  if (state.matchedItemIds.contains(itemId)) return state;

  final selected = state.feedback.selected;
  if (selected == null) {
    return state.copyWith(
      feedback: state.feedback.copyWith(
        selected: MatchCardRef(side: side, itemId: itemId),
      ),
    );
  }
  if (selected.side == side) {
    final same = selected.itemId == itemId;
    return state.copyWith(
      feedback: same
          ? state.feedback.copyWith(clearSelected: true)
          : state.feedback.copyWith(
              selected: MatchCardRef(side: side, itemId: itemId),
            ),
    );
  }
  return selected.itemId == itemId
      ? _match(state, selected, itemId)
      : _miss(state, selected, MatchCardRef(side: side, itemId: itemId));
}

MatchBoardState _match(
  MatchBoardState state,
  MatchCardRef selected,
  int itemId,
) {
  final core = state.core.recordCorrect(
    itemId: itemId,
    answerMs: state.feedback.sinceLastMatchMs,
  );
  final matched = <int>{...state.matchedItemIds, itemId};
  final next = state.copyWith(
    core: core,
    matchedItemIds: matched,
    feedback: const MatchFeedback(),
  );
  return matched.length >= state.pairs.length
      ? next.copyWith(core: next.core.finish())
      : next;
}

MatchBoardState _miss(
  MatchBoardState state,
  MatchCardRef selected,
  MatchCardRef tapped,
) {
  // 旧版一次错配只推高一次失误计数，但把两张牌都标记为「曾失误」；
  // 先 recordMistake（计数 + 连击清零 + 标记），再 flagMistake 标记另一张。
  final core = state.core
      .recordMistake(itemId: selected.itemId)
      .flagMistake(itemId: tapped.itemId);
  return state.copyWith(
    core: core,
    feedback: state.feedback.copyWith(
      wrongFlash: <String>{selected.key, tapped.key},
    ),
  );
}
