/// 拼写题的渐进式提示。
///
/// 对应旧版 `src/app/(main)/study/study-client.tsx` 的 `getHintPattern` 与
/// `getProgressiveHint`。放在 `lib/domain/` 是刻意的：它纯粹是字符串构造，
/// 与界面无关，可以逐字符断言「露了几个字母、留了几个空」。
///
/// **为什么边界值是参数而不是常量**：`lib/domain/**` 禁止裸数字字面量
/// （见 `test/architecture/architecture_test.dart`），而「至少几个字母才给提示」
/// 「多长算长词」属于展示规则、不是领域不变量，取值由界面层决定
/// （见 `features/study/study_hint_bar.dart`）。
library;

import 'dart:math' as math;

final RegExp _whitespace = RegExp(r'\s');

/// 基础提示模式：露出首尾字母，中间全部留空。
///
/// `edgeLetterCount` 是首尾各露出的字母个数，同时也是最短词条长度：再短就
/// 等于直接把答案给出去。`longTermLength` 以上的词条改用连续下划线——逐字符
/// 留空会把长词的提示行撑出屏幕。
///
/// 含空白的词条返回 `null`：短语与句子不给字母提示，空格本身已经暴露了词形。
String? getHintPattern(
  String term, {
  required int edgeLetterCount,
  required int longTermLength,
}) {
  if (!_canHint(term, edgeLetterCount)) return null;
  final middle = _middleBlanks(
    term,
    term.length - edgeLetterCount,
    longTermLength,
  );
  return '${term[0]} $middle ${term[term.length - 1]}';
}

/// 渐进式提示：每多按一次提示，中间就多露出一个字母。
///
/// `level` 为 0 时就是基础模式；`level` 再大也只露到倒数第二个字母——
/// 最后一个字母必须由用户自己写出来。
String? getProgressiveHint(
  String term,
  int level, {
  required int edgeLetterCount,
  required int longTermLength,
}) {
  if (!_canHint(term, edgeLetterCount)) return null;
  if (level <= 0) {
    return getHintPattern(
      term,
      edgeLetterCount: edgeLetterCount,
      longTermLength: longTermLength,
    );
  }
  final middleCount = term.length - edgeLetterCount;
  final revealCount = math.min(middleCount, level + 1);
  final separator = term.length > longTermLength ? '' : ' ';
  final revealed = term.substring(1, 1 + revealCount).split('').join(separator);
  final remaining = middleCount - revealCount;
  final middle = remaining <= 0
      ? revealed
      : '$revealed$separator${_middleBlanks(term, remaining, longTermLength)}';
  return '${term[0]} $middle ${term[term.length - 1]}';
}

/// 提示是否已经用尽——再点也不会多露出一个字母。
///
/// 界面的禁用条件与它共用同一个判定：写成两处（按钮一处、快捷键一处）
/// 迟早会出现「按钮灰了但快捷键还能点」。
bool isHintExhausted(String term, int level, {required int edgeLetterCount}) =>
    level >= term.length - edgeLetterCount;

/// 是否满足给出提示的最低条件。
bool _canHint(String term, int edgeLetterCount) =>
    term.length > edgeLetterCount && !_whitespace.hasMatch(term);

/// 中间留空：长词连成一片，短词逐字符留空。
String _middleBlanks(String term, int count, int longTermLength) =>
    term.length > longTermLength ? _blanks(count) : _spacedBlanks(count);

String _blanks(int count) => '_' * count;

String _spacedBlanks(int count) => List<String>.filled(count, '_').join(' ');
