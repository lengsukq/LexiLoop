/// 音标训练页面（`/phonetics`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/phonetics/phonetics_play_view.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/features/phonetics/phonetics_setup_view.dart';
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
          onReplay: controller.start,
          onExit: controller.exit,
        ),
        PhoneticSaveFailed() => GameErrorView(
          message: '结算失败：${state.message}',
          onRetry: controller.retrySave,
        ),
      },
    );
  }
}
