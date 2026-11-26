/// 游戏类页面（小游戏 / 配对 / 音标）共用的外壳与 HUD。
///
/// 这三个页面都是**沉浸式**路由（`destinations.dart` 的 `immersivePaths`），
/// 不渲染导航外壳，因此背景光晕要自己铺；页头、进度条、连击/失误展示
/// 也完全一致，做成共用组件可以避免三份实现各自漂移。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 游戏类页面的统一外壳：环境光背景 + 安全区 + 居中的内容宽度。
class GameScaffold extends StatelessWidget {
  /// 以内容构造。
  const new({required this.child, this.onBack, this.maxWidth = 760, super.key});

  /// 页面内容。
  final Widget child;

  /// Android 系统返回和桌面后退的处理方式，由当前游戏阶段决定。
  final VoidCallback? onBack;

  /// 内容最大宽度（macOS 宽窗口下避免元素被拉到屏幕两端）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // 背景由顶层路由的包装统一画（`app/router.dart` 的 `_capped`）：
    // 这里再画一层会让小游戏/配对/音标比其他页光斑更浓。
    return PopScope<Object?>(
      // 顶层沉浸路由通常不能 pop。阻止 Android 将返回键解释为退出应用。
      canPop: GoRouter.maybeOf(context) == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (onBack != null) {
          onBack!();
        } else {
          GoRouter.maybeOf(context)?.go('/');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  LexiSpace.s16,
                  LexiSpace.s12,
                  LexiSpace.s16,
                  LexiSpace.s16,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 页头：倒计时进度、得分、连击、失误与退出按钮。
class GameHud extends StatelessWidget {
  /// 以各字段构造。
  const new({
    required this.title,
    required this.core,
    required this.onExit,
    this.mistakeLabel = '失误',
    super.key,
  });

  /// 模式标题。
  final String title;

  /// 计分内核。
  final GameCoreState core;

  /// 退出回调。
  final VoidCallback onExit;

  /// 失误计数的标签（配对叫「错配」）。
  final String mistakeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final ratio = core.plan.durationMs <= 0
        ? 0.0
        : core.remainingMs / core.plan.durationMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$title · 第 ${core.progress.index + 1}/${core.plan.itemCount} 题',
                style: LexiType.body.copyWith(
                  color: colors.secondaryLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(core.remainingMs / 1000).ceil()}s',
              style: LexiType.callout.copyWith(
                color: ratio < 0.25 ? colors.dangerText : colors.label,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: LexiSpace.s8),
            IconButton(
              onPressed: onExit,
              icon: const Icon(LucideIcons.x, size: 20),
              tooltip: '退出',
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.pill),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 5,
            backgroundColor: colors.fill,
          ),
        ),
        const SizedBox(height: LexiSpace.s10),
        Surface(
          variant: SurfaceVariant.inset,
          borderRadius: BorderRadius.circular(LexiRadius.pill),
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s12,
            vertical: LexiSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              _Stat(label: '得分', value: '${core.tally.score}'),
              _Stat(label: '连击', value: '×${core.tally.combo}'),
              _Stat(label: mistakeLabel, value: '${core.tally.mistakeCount}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: LexiType.title.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 结算失败页上「回到刚才那一轮」的按钮文案。
///
/// 三个家族（小游戏 / 配对 / 音标）共用同一个说法：用户看到的应当是
/// 「我的一轮还在」，而不是「重试」这种对自己没把握的词。
const String resumeRoundLabel = '继续本轮';

/// 错误态：带重试按钮的中文提示。
///
/// **为什么有第二个出口**：结算失败时这一轮的成绩还在内存里
/// （`MatchSaveFailed.previous` / `PhoneticSaveFailed.previous`），
/// 三个控制器也各自提供了 `resumeAfterSaveFailure()` 回到那一轮。
/// 收敛前那个方法**零调用**，界面上只有「重试」——对用户来说
/// 「重试」失败之后的选择只剩离开，而离开就把刚打完的一轮丢了。
class GameErrorView extends StatelessWidget {
  /// 以提示、重试回调与可选第二出口构造。
  const new({
    required this.message,
    required this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  /// 提示文案。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  /// 第二出口的文案。
  final String? secondaryLabel;

  /// 第二出口的回调。
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(LucideIcons.circleAlert, size: 38, color: colors.danger),
            const SizedBox(height: LexiSpace.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: LexiSpace.s14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (secondaryLabel != null && onSecondary != null) ...<Widget>[
                  OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                  const SizedBox(width: LexiSpace.s12),
                ],
                FilledButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 模式标题。
String gameModeTitle(GameMode mode) => switch (mode) {
  GameMode.wordBuilder => '单词拼图',
  GameMode.listeningPick => '听音辨词',
  GameMode.meaningBlitz => '词义冲刺',
  GameMode.whackAMole => '词汇地鼠',
  GameMode.wordStack => '单词堆堆乐',
  GameMode.wordTetris => '词汇俄罗斯方块',
  GameMode.match => '限时词汇配对',
  GameMode.phonetics => '音标辨音训练',
};
