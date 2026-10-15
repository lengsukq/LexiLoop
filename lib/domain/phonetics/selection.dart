/// 音标训练的选题与出题规则。
///
/// 对应旧版 `modules/phonetics/selection.ts`（`selectPhoneticCandidates` /
/// `createPhoneticItems`）与 `app/(main)/phonetics/choice.ts`。
///
/// **与旧版的差异（有意，且必须如此）**：旧版从数据库里挑「有音标的词条」，
/// 干扰项按音标字符串相似度（共享字符数、重音符号是否一致、长度差）排序，
/// 完全不看 `catalog.ts` 的分类。本版保留「从真实词条出题」这一骨架
/// （`study_session_items.word_id` 有外键，题目必须挂在真实词条上），
/// 但把干扰项的来源换成目录：
/// 1. 先把词条的音标**归到目录条目**（[matchPhoneme]，最长符号优先、元音优先）；
/// 2. 干扰项优先取「与正确项易混（`confusable`）或同类」的词条音标，
///    不足时再用其余候选补齐。
/// 这样「易混音标组」这套教学资产才真正参与出题，而不是只躺在目录里。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 音标训练的题型（对应旧版 `PHONETIC_CHALLENGE_TYPES`）。
enum PhoneticChallengeType {
  /// 听发音选音标。
  soundToPhonetic('SOUND_TO_PHONETIC'),

  /// 看音标选例词。
  phoneticToWord('PHONETIC_TO_WORD'),

  /// 看单词选音标。
  wordToPhonetic('WORD_TO_PHONETIC');

  new(this.wire);

  /// 稳定标识。
  final String wire;

  /// 该题型的选项是否是音标（否则是单词）。
  bool get hasPhoneticChoices => this != PhoneticChallengeType.phoneticToWord;
}

/// 一个词条的语音信息。
class PhoneticSound {
  /// 以各字段构造。
  const new({required this.phonetic, required this.entry});

  /// 词条的展示音标（含斜杠，如 `/ʃiːp/`）。
  final String phonetic;

  /// 该音标归到的目录条目（用于解析与同类干扰项）。
  final PhonemeEntry entry;
}

/// 音标训练的一个候选词条。
class PhoneticSource {
  /// 以各字段构造。
  const new({
    required this.itemId,
    required this.wordId,
    required this.word,
    required this.phonetic,
    required this.priority,
  });

  /// 会话题目 ID。
  final int itemId;

  /// 词条 ID。
  final int wordId;

  /// 词条与释义。
  final GameWord word;

  /// 词条的展示音标。
  final String phonetic;

  /// 候选优先级。
  final GamePriority priority;
}

/// 一道音标训练题。
class PhoneticQuestion {
  /// 以各字段构造。
  const new({required this.base, required this.sound, required this.challenge});

  /// 复用游戏题目结构（选项、词条、优先级都在这里）。
  final GameQuestion base;

  /// 语音信息。
  final PhoneticSound sound;

  /// 题型。
  final PhoneticChallengeType challenge;

  /// 该题的正确选项文本。
  String get answer => challenge == PhoneticChallengeType.phoneticToWord
      ? base.word.term
      : sound.phonetic;

  /// 解析用的目录条目。
  PhonemeEntry get entry => sound.entry;
}

/// 把词条音标归到目录条目上。
///
/// 匹配规则：取「出现在音标串里」的最长符号；长度相同时元音优先
/// （`/kæt/` 归到 `æ` 而不是 `t`），因为音标训练要练的是元音对立。
/// 一个都没命中时返回 `null`（调用方据此跳过该词条）。
PhonemeEntry? matchPhoneme(
  String phonetic, {
  List<PhonemeEntry> catalog = phonemeCatalog,
}) {
  final normalized = _identity(phonetic);
  if (normalized.isEmpty) return null;
  PhonemeEntry? best;
  for (final entry in catalog) {
    if (!normalized.contains(_identity(entry.symbol))) continue;
    if (best == null || _isBetterMatch(entry, best)) best = entry;
  }
  return best;
}

/// 音标串的比较用归一化形式：去掉斜杠、方括号、空白。
String _identity(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s/\[\]]+'), '');

/// 候选 [candidate] 是否比 [current] 更该作为归属条目。
bool _isBetterMatch(PhonemeEntry candidate, PhonemeEntry current) {
  if (candidate.symbol.length != current.symbol.length) {
    return candidate.symbol.length > current.symbol.length;
  }
  return candidate.kind != PhonemeKind.consonant &&
      current.kind == PhonemeKind.consonant;
}

/// 生成音标训练题。
///
/// [sources] 是已经带好音标的候选词条；候选不足
/// [phoneticMinimumItemCount] 个、或凑不出 [phoneticChoiceCount] 个互不重复的
/// 选项时抛 [AppErrorCode.notEnoughPhoneticWords]。
List<PhoneticQuestion> buildPhoneticQuestions({
  required List<PhoneticSource> sources,
  required int count,
  required double Function() random,
}) {
  if (sources.length < phoneticMinimumItemCount) {
    throw const ConflictError(AppErrorCode.notEnoughPhoneticWords);
  }
  final picked = shuffleWith(
    sources,
    random,
  ).take(count).toList(growable: false);
  return <PhoneticQuestion>[
    for (var index = 0; index < picked.length; index += 1)
      _buildQuestion(
        source: picked[index],
        sources: sources,
        challenge: _challengeFor(index),
        random: random,
      ),
  ];
}

/// 按顺序循环三种题型（与旧版 `index % 3` 一致）。
PhoneticChallengeType _challengeFor(int index) =>
    PhoneticChallengeType.values[index % PhoneticChallengeType.values.length];

PhoneticQuestion _buildQuestion({
  required PhoneticSource source,
  required List<PhoneticSource> sources,
  required PhoneticChallengeType challenge,
  required double Function() random,
}) {
  final entry = matchPhoneme(source.phonetic);
  if (entry == null) {
    throw const ConflictError(AppErrorCode.notEnoughPhoneticWords);
  }
  final sound = PhoneticSound(phonetic: source.phonetic, entry: entry);
  final pool = challenge.hasPhoneticChoices
      ? _phoneticPool(source: source, sources: sources)
      : _wordPool(source: source, sources: sources);
  final options = createChoicePool(
    correct: challenge.hasPhoneticChoices ? sound.phonetic : source.word.term,
    pool: pool,
    size: phoneticChoiceCount,
    random: random,
  );
  if (options.length < phoneticChoiceCount) {
    throw const ConflictError(AppErrorCode.notEnoughPhoneticWords);
  }
  return PhoneticQuestion(
    base: GameQuestion(
      itemId: source.itemId,
      wordId: source.wordId,
      word: source.word,
      choices: GameChoices(
        options: options,
        definitions: <String, String>{
          for (final other in sources) other.word.term: other.word.definition,
        },
      ),
      priority: source.priority,
    ),
    sound: sound,
    challenge: challenge,
  );
}

/// 音标类选项的候选池：易混与同类的排在前面。
List<String> _phoneticPool({
  required PhoneticSource source,
  required List<PhoneticSource> sources,
}) {
  final entry = matchPhoneme(source.phonetic);
  final related = <String>[];
  final others = <String>[];
  final seen = <String>{_identity(source.phonetic)};
  for (final other in sources) {
    if (!seen.add(_identity(other.phonetic))) continue;
    final otherEntry = matchPhoneme(other.phonetic);
    final similar =
        entry != null &&
        otherEntry != null &&
        (entry.similarPhonemes.contains(otherEntry.symbol) ||
            entry.category == otherEntry.category);
    (similar ? related : others).add(other.phonetic);
  }
  return <String>[...related, ...others];
}

/// 单词类选项的候选池：同类的排在前面。
List<String> _wordPool({
  required PhoneticSource source,
  required List<PhoneticSource> sources,
}) {
  final entry = matchPhoneme(source.phonetic);
  final related = <String>[];
  final others = <String>[];
  final seen = <String>{source.word.term.trim().toLowerCase()};
  for (final other in sources) {
    if (!seen.add(other.word.term.trim().toLowerCase())) continue;
    final otherEntry = matchPhoneme(other.phonetic);
    final similar =
        entry != null &&
        otherEntry != null &&
        (entry.similarPhonemes.contains(otherEntry.symbol) ||
            entry.category == otherEntry.category);
    (similar ? related : others).add(other.word.term);
  }
  return <String>[...related, ...others];
}
