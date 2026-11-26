/// 二级页面与沉浸流通用顶栏（Mobile-First）。
///
/// 解决此前详情页、学习页、小游戏页用 `Wrap` 堆叠返回按钮导致移动端顶栏折行、
/// 随滚动滚走或触控热区不统一的问题。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 通用二级页面顶栏。
class LexiTopBar extends StatelessWidget {
  /// 以标题、返回回调与右侧操作项构造。
  const new({
    required this.title,
    this.onBack,
    this.subtitle,
    this.trailing = const <Widget>[],
    super.key,
  });

  /// 顶栏主标题。
  final String title;

  /// 左侧返回或关闭回调；为空时不渲染返回按钮。
  final VoidCallback? onBack;

  /// 可选副标题或说明文案。
  final String? subtitle;

  /// 右侧紧凑操作按钮组。
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final sub = subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s12),
      child: Row(
        children: <Widget>[
          if (onBack case final backCallback?) ...<Widget>[
            _BackButton(onTap: backCallback),
            const SizedBox(width: LexiSpace.s8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LexiType.title.copyWith(color: colors.label),
                ),
                if (sub != null && sub.isNotEmpty)
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...<Widget>[
            const SizedBox(width: LexiSpace.s8),
            Row(mainAxisSize: MainAxisSize.min, children: trailing),
          ],
        ],
      ),
    );
  }
}

/// 满足 44pt 触控下限的返回按钮。
class _BackButton extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Semantics(
      button: true,
      label: '返回',
      child: SizedBox(
        width: LexiLayout.minTapTarget,
        height: LexiLayout.minTapTarget,
        child: IconButton(
          onPressed: () {
            LexiHaptics.light();
            onTap();
          },
          tooltip: '返回',
          style: IconButton.styleFrom(
            backgroundColor: colors.fill,
            foregroundColor: colors.label,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LexiRadius.md),
            ),
          ),
          icon: const Icon(LucideIcons.arrowLeft, size: 18),
        ),
      ),
    );
  }
}
