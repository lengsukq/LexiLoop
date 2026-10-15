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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                style: TextStyle(
                  color: colors.secondaryLabel,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${(core.remainingMs / 1000).ceil()}s',
              style: TextStyle(
                color: ratio < 0.25 ? colors.danger : colors.label,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onExit,
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: '退出',
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 5,
            backgroundColor: colors.fill,
          ),
        ),
        const SizedBox(height: 10),
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
            style: TextStyle(
              color: colors.label,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// 空态：题库不足或功能不可用时的中文提示。
class GameEmptyView extends StatelessWidget {
  /// 以提示与图标构造。
  const new({
    required this.message,
    this.icon = Icons.inbox_rounded,
    super.key,
  });

  /// 提示文案。
  final String message;

  /// 图标。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: colors.tertiaryLabel),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13.5),
            ),
          ],
        ),
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 38, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// 题干卡片：中文释义（小游戏）或音标/单词（音标训练）。
class GamePromptCard extends StatelessWidget {
  /// 以题干与提示构造。
  const new({
    required this.hint,
    required this.prompt,
    this.promptStyle,
    this.footer,
    super.key,
  });

  /// 顶部提示（说明这一题要做什么）。
  final String hint;

  /// 题干主体。
  final String prompt;

  /// 题干样式（音标训练用等宽大字号）。
  final TextStyle? promptStyle;

  /// 题干下方的附加内容（朗读按钮、释义等）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      children: <Widget>[
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.quaternaryLabel,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          prompt,
          textAlign: TextAlign.center,
          style:
              promptStyle ??
              TextStyle(
                color: colors.label,
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
        ),
        if (footer != null) ...<Widget>[const SizedBox(height: 12), footer!],
      ],
    );
  }
}

/// 模式标题。
String gameModeTitle(GameMode mode) => switch (mode) {
  GameMode.wordBuilder => '单词拼图',
  GameMode.whackAMole => '词汇地鼠',
  GameMode.wordStack => '单词堆堆乐',
  GameMode.wordTetris => '词汇俄罗斯方块',
  GameMode.match => '限时词汇配对',
  GameMode.phonetics => '音标辨音训练',
};
