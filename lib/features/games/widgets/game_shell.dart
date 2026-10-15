/// 游戏类页面（小游戏 / 配对 / 音标）共用的外壳与 HUD。
///
/// 这三个页面都是**沉浸式**路由（`destinations.dart` 的 `immersivePaths`），
/// 不渲染导航外壳，因此背景光晕要自己铺；页头、进度条、连击/失误展示
/// 也完全一致，做成共用组件可以避免三份实现各自漂移。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 游戏类页面的统一外壳：环境光背景 + 安全区 + 居中的内容宽度。
class GameScaffold extends StatelessWidget {
  /// 以内容构造。
  const new({required this.child, this.maxWidth = 760, super.key});

  /// 页面内容。
  final Widget child;

  /// 内容最大宽度（macOS 宽窗口下避免元素被拉到屏幕两端）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
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
                color: ratio < 0.25 ? colors.danger : colors.label,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: LexiSpace.s8),
            IconButton(
              onPressed: onExit,
              icon: const Icon(Icons.close_rounded, size: 20),
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
        Row(
          children: <Widget>[
            _Stat(label: '得分', value: '${core.tally.score}'),
            _Stat(label: '连击', value: '×${core.tally.combo}'),
            _Stat(label: mistakeLabel, value: '${core.tally.mistakeCount}'),
          ],
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

/// 错误态：带重试按钮的中文提示。
class GameErrorView extends StatelessWidget {
  /// 以提示与重试回调构造。
  const new({required this.message, required this.onRetry, super.key});

  /// 提示文案。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 38, color: colors.danger),
            const SizedBox(height: LexiSpace.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: LexiSpace.s14),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
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
