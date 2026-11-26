/// 题目载荷的构造：选项去重、填空句、字母拼图块。
///
/// 对应旧版 `modules/study/view.ts` 的 `shuffle`、`buildClozeExtra` 与
/// `buildLetterTiles`，以及散落在 `generateMeaningChoices` /
/// `generateWordChoices` 里 6 遍的「遍历候选 → 判空 → 去重 → 够了就停」。
///
/// 与旧版最大的差别是**随机源注入**：旧版直接调 `Math.random()`，
/// 「给定随机序列应得到什么结果」无法断言，测试只能写「结果在集合内」
/// 这类弱断言；这里所有随机都走 `double Function()` 参数。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 就地打乱的副本（Fisher–Yates）。random 返回 [0,1)。
///
/// 「副本」指不修改入参：旧版 `shuffle` 直接改传入数组，调用方若还持有
/// 原数组（例如模块级候选池）会被静默打乱。返回新列表更安全，
/// 代价是一次浅拷贝——选项最多几条，可以忽略。
List<T> shuffleWith<T>(List<T> items, double Function() random) {
  final result = List<T>.of(items);
  for (var index = result.length - 1; index > 0; index -= 1) {
    final other = _randomIndex(random, index + 1);
    final swapped = result[index];
    result[index] = result[other];
    result[other] = swapped;
  }
  return result;
}

/// 构造填空题载荷。找不到合适例句时返回 null。
///
/// 优先挑「句子里真的出现该词」的例句：拿一句不含目标词的句子挖空，
/// 用户没有任何线索可判断该填什么。都不含时退回第一条例句。
ClozePayload? buildCloze(String term, List<ExampleView> examples) {
  final keyword = term.trim();
  // 空词条无从挖空：`\b\b` 会匹配每个词边界，把整句插满占位符。
  if (keyword.isEmpty) return null;
  final candidates = _clozeCandidates(examples);
  if (candidates.isEmpty) return null;

  final pattern = RegExp(
    r'\b' + RegExp.escape(keyword) + r'\b',
    caseSensitive: false,
  );
  final chosen = candidates.firstWhere(
    (item) => pattern.hasMatch(item.sentence),
    orElse: () => candidates.first,
  );
  final blanked = chosen.sentence.replaceAll(pattern, clozeBlankToken);

  return ClozePayload(
    sentence: chosen.sentence,
    // 兜底为什么存在：词边界匹配要求目标词是独立单词。term 是 `cat`
    // 而例句里只有 `category` 时正则一处也不命中，此时把原句原样交给
    // 用户等于直接给出答案，所以退回一次「大小写敏感、无词边界」的
    // 字面替换——宁可挖错位置，也不能不挖。
    blankedSentence: blanked == chosen.sentence
        ? chosen.sentence.replaceFirst(keyword, clozeBlankToken)
        : blanked,
    translation: chosen.translation,
  );
}

/// 构造字母拼图块。同一字母的不同位置必须有不同的 id。
///
/// id 用「下标-字符」而不是字符本身：`apple` 里的两个 `p` 若共用 id，
/// 拖拽时会互相顶替，用户永远拼不对。
List<LetterTile> buildLetterTiles(
  String term, {
  required double Function() random,
}) {
  // 按 rune 而不是 UTF-16 码元切分：旧版 JS 的 `[...term]` 也是按码点迭代，
  // 用 `split('')` 会把 emoji 之类的代理对拆成两个坏块。
  final characters = term.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  final tiles = <LetterTile>[];
  for (var index = 0; index < characters.length; index += 1) {
    final value = characters[index];
    tiles.add(LetterTile(id: '$index-$value', value: value));
  }

  final shuffled = shuffleWith(tiles, random);
  if (shuffled.length > 1 && _sameOrderAsTerm(shuffled, term)) {
    // 打乱后恰好等于原词时把首块挪到末尾：否则用户看到的就是答案本身，
    // 这道题白送。旧版的处理方式保留。
    return <LetterTile>[...shuffled.skip(1), shuffled.first];
  }
  return shuffled;
}

/// 把一串候选文本去重后追加进结果，直到达到 limit。
///
/// 比较时忽略大小写与首尾空白：旧版把同一段「遍历候选 → 判空 → 去重 →
/// 够了就停」在 `generateMeaningChoices` 与 `generateWordChoices` 里抄了
/// 6 遍（3 个候选来源 × 2 个函数），任何一处漏了 `toLocaleLowerCase()`
/// 都会让同一条释义以两种大小写出现在同一道题里。收敛到一处后，
/// 去重规则只有这一个实现。
///
/// [seed] 里的项直接进入结果，并计入去重集合与 [limit]；它们本身不会被
/// 再次追加。[candidates] 里的 `null` 与空白项被跳过。
List<String> collectDistinct(
  List<String> seed,
  Iterable<String?> candidates, {
  required int limit,
}) {
  final result = List<String>.of(seed);
  final seen = <String>{for (final item in seed) _dedupeKey(item)};
  // 种子已满时连迭代器都不碰：candidates 可能是惰性的数据库游标，
  // 让它先吐一条再丢弃是白跑一次查询。
  if (result.length >= limit) return result;

  for (final candidate in candidates) {
    if (result.length >= limit) break;
    final text = candidate?.trim();
    if (text == null || text.isEmpty) continue;
    if (!seen.add(_dedupeKey(text))) continue;
    result.add(text);
  }
  return result;
}

/// 去重比较用的键：忽略大小写与首尾空白。
///
/// 旧版只在部分分支做了 `toLocaleLowerCase()`，且从不 trim，
/// 于是 `"Apple"` 与 `" apple "` 会同时出现在选项里。
String _dedupeKey(String text) => text.trim().toLowerCase();

/// 取 `[0, bound)` 内的随机下标。
///
/// 契约上 [random] 返回 `[0, 1)`，但假随机源可能返回 1.0，那会让 `floor()`
/// 正好落到 `bound` 上并抛 `RangeError`。测试替身不该让生产代码崩，
/// 故在此夹紧而不是信任调用方。
int _randomIndex(double Function() random, int bound) {
  final scaled = (random() * bound).floor();
  if (scaled < 0) return 0;
  return scaled >= bound ? bound - 1 : scaled;
}

/// 判断拼图块顺序是否与原词完全一致（忽略大小写）。
bool _sameOrderAsTerm(List<LetterTile> tiles, String term) {
  final joined = tiles.map((tile) => tile.value).join();
  return joined.toLowerCase() == term.toLowerCase();
}

/// 取出「句子非空」的例句，并去掉句子首尾空白。
List<_ClozeCandidate> _clozeCandidates(List<ExampleView> examples) {
  final candidates = <_ClozeCandidate>[];
  for (final example in examples) {
    final sentence = example.sentence.trim();
    if (sentence.isEmpty) continue;
    candidates.add(
      _ClozeCandidate(sentence: sentence, translation: example.translation),
    );
  }
  return candidates;
}

/// 一条可用于挖空的例句（句子已 trim）。
class _ClozeCandidate {
  /// 以句子与可选翻译构造。
  const new({required this.sentence, this.translation});

  /// 例句原文（已 trim）。
  final String sentence;

  /// 例句翻译，可能没有。
  final String? translation;
}
