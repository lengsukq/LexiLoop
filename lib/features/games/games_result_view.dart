/// 小游戏结算页。
///
/// 把 [GamesFinished] 里的逐题结果折叠成「失误词条」列表，
/// 其余展示交给共用的 `GameResultPanel`。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/games/game_mistake.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';

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
      mistakes: gameMistakesFor(
        questions: finished.questions,
        outcomes: finished.outcomes,
      ),
      onOpenWord: (wordId) => context.go('$wordDetailPathPrefix$wordId'),
      onReplay: onReplay,
      onExit: onExit,
    );
  }
}
