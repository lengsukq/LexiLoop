/// 单词堆堆乐的渲染层。
///
/// 只负责把候选词块画成两行、把塔层画出来，点击翻译成 `TapStackBlock`。
/// 冷却（点错后不可再点）与塔高全由状态机维护。
///
/// **与旧版的差异**：旧版两行词块是无限滚动动画（`block-scroll-left/right`），
/// 这里渲染成静态的两行网格——滚动只是视觉噪音，反而让用户更难瞄准；
/// 塔层只展示最近 [wordStackTowerVisibleCount] 层，与旧版一致。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/word_stack.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 单词堆堆乐视图。
class WordStackView extends StatelessWidget {
  /// 以状态与派发回调构造。
  const new({required this.state, required this.onAction, super.key});

  /// 状态机状态。
  final WordStackState state;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final question = state.current;
    if (question == null) return const SizedBox.shrink();

    final options = question.choices.options;
    final half = (options.length / 2).ceil();
    final tower = state.tower;
    final visible = tower.length > wordStackTowerVisibleCount
        ? tower.sublist(tower.length - wordStackTowerVisibleCount)
        : tower;

    return Column(
      children: <Widget>[
        Text(
          '看释义，点选滚动词块堆高塔',
          style: LexiType.footnote.copyWith(color: colors.quaternaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          question.word.definition,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: LexiSpace.s14),
        _Row(
          words: options.take(half).toList(),
          state: state,
          onAction: onAction,
        ),
        const SizedBox(height: LexiSpace.s8),
        _Row(
          words: options.skip(half).toList(),
          state: state,
          onAction: onAction,
        ),
        const SizedBox(height: LexiSpace.s16),
        SizedBox(
          height: _stackAreaHeight,
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    '点对词块，塔会越堆越高',
                    style: LexiType.footnote.copyWith(
                      color: colors.tertiaryLabel,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    for (var index = 0; index < visible.length; index += 1)
                      Padding(
                        padding: const EdgeInsets.only(top: LexiSpace.s4),
                        child: _TowerBlock(
                          term: visible[index],
                          index: tower.length - visible.length + index,
                        ),
                      ),
                  ],
                ),
        ),
        Text(
          '已堆 ${tower.length} 层 · 点错会记一次失误',
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const new({required this.words, required this.state, required this.onAction});

  final List<String> words;
  final WordStackState state;
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: <Widget>[
        for (final word in words)
          Opacity(
            opacity: state.isDropped(word) ? 0.25 : 1,
            child: Material(
              color: colors.fill,
              borderRadius: BorderRadius.circular(LexiRadius.md),
              child: InkWell(
                onTap: state.isDropped(word) || state.popped
                    ? null
                    : () => onAction(TapStackBlock(word)),
                borderRadius: BorderRadius.circular(LexiRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LexiSpace.s20,
                    vertical: LexiSpace.s12,
                  ),
                  child: Text(
                    word,
                    style: LexiType.callout.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TowerBlock extends StatelessWidget {
  const new({required this.term, required this.index});

  final String term;
  final int index;

  /// 塔层配色循环。
  ///
  /// 收编前这里是四个写死的 iOS 系统色（`0xFFFF9500` / `0xFF5AC8FA` /
  /// `0xFFAF52DE` / `0xFF34C759`）。游戏方块确实需要可区分的颜色，但这四个
  /// 值绕过了 `LexiColors`：深色模式下它们不会跟着界面调整，而且与状态徽章、
  /// 图表用的是两套「橙 / 蓝 / 紫 / 绿」。现在直接用语义色板。
  static List<Color> colorsOf(LexiColors palette) => <Color>[
    palette.warning,
    palette.accent,
    palette.purple,
    palette.success,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorsOf(context.lexiColors)[index % blockColorCount],
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        term,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LexiType.footnote.copyWith(
          // 白字压在饱和填充上（见 tetris 同一处注释）。
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 堆塔区高度——固定高度让塔身增长时下方的操作区不位移。
const double _stackAreaHeight = 108;

/// 塔层配色的循环长度。
const int blockColorCount = 4;
