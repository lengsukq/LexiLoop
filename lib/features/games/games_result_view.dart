/// 小游戏结算页。
///
/// 把 [GamesFinished] 里的逐题结果折叠成「失误词条」列表，
/// 其余展示交给共用的 `GameResultPanel`。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';

/// 小游戏结算页。
class GamesResultView extends StatelessWidget {
  /// 以结算状态与回调构造。
  const new({
    required this.finished,
    required this.onReplay,
    required this.onExit,
    super.key,
  });

  /// 结算状态。
  final GamesFinished finished;

  /// 再来一局。
  final VoidCallback onReplay;

  /// 返回准备页。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final mode = finished.result.mode;
    return GameResultPanel(
      labels: GameResultLabels(
        title: '${gameModeTitle(mode)}得分',
        primary: '一次正确',
        missed: '未完成',
        exit: '选择其他游戏',
      ),
      result: finished.result,
      mistakes: mistakeLines(finished),
      onReplay: onReplay,
      onExit: onExit,
    );
  }
}

/// 把逐题结果折叠成「词条 · 释义」的失误列表。
///
/// 抽成顶层函数而不是内联在 `build` 里：一是 `build()` 有 80 行上限，
/// 二是这条折叠规则与结算页的排版无关，测试可以直接断言它。
List<String> mistakeLines(GamesFinished finished) {
  final lines = <String>[];
  for (var index = 0; index < finished.questions.length; index += 1) {
    if (index >= finished.outcomes.length) break;
    if (finished.outcomes[index] == GameOutcome.firstTry) continue;
    final word = finished.questions[index].word;
    lines.add('${word.term} · ${word.definition}');
  }
  return lines;
}

/// 该局模式的标题（结算页用）。
String resultTitle(GameMode mode) => '${gameModeTitle(mode)}得分';
