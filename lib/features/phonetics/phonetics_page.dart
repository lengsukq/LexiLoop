/// 音标训练页面（`/phonetics`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/phonetics/phonetics_play_view.dart';
import 'package:lexiloop/features/phonetics/phonetics_providers.dart';
import 'package:lexiloop/features/phonetics/phonetics_setup_view.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

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
        PhoneticSaving() => const _SavingView(),
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

class _SavingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            '正在结算…',
            style: TextStyle(
              color: context.lexiColors.secondaryLabel,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
