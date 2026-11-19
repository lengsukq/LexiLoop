/// 音标训练页面（`/phonetics`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/phonetics/phonetics_play_view.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/features/phonetics/phonetics_setup_view.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/widgets/settling_indicator.dart';

/// 音标训练页面。
class PhoneticsPage extends ConsumerWidget {
  /// 创建音标训练页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phoneticControllerProvider);
    final controller = ref.read(phoneticControllerProvider.notifier);

    return GameScaffold(
      onBack: () {
        if (state is PhoneticSaving) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('正在保存成绩，保存完成后再返回')));
        } else if (state is PhoneticSetup) {
          context.go(gamesPath);
        } else {
          controller.exit();
        }
      },
      child: switch (state) {
        PhoneticSetup() => PhoneticsSetupView(
          state: state,
          onSelectAccent: controller.selectAccent,
          onStart: controller.start,
        ),
        PhoneticPlaying() => PhoneticPlayView(
          playing: state,
          onAction: controller.dispatch,
          onExit: controller.exit,
        ),
        PhoneticSaving() => const SettlingIndicator(),
        PhoneticFinished() => PhoneticsResultView(
          result: state.result,
          // 结算态不是准备态：走 restart()，否则 start() 的守卫会让
          // 「再来一局」静默失效。
          onReplay: controller.restart,
          onExit: controller.exit,
        ),
        PhoneticSaveFailed() => GameErrorView(
          message: '结算失败：${state.message}',
          onRetry: controller.retrySave,
          secondaryLabel: resumeRoundLabel,
          onSecondary: controller.resumeAfterSaveFailure,
        ),
      },
    );
  }
}
