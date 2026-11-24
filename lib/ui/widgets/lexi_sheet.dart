/// 移动端通用底部抽屉（Bottom Sheet）容器。
///
/// 统一带顶部拖拽指示条（Drag Handle）、圆角顶盖、安全区内边距与标题栏，
/// 让过滤面板、快速加词、确认抽屉、后台补全状态抽屉拥有一致的原生手感。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 通用底部抽屉外壳。
class LexiSheet extends StatelessWidget {
  /// 以标题与子内容构造。
  const new({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  /// 可选抽屉标题。
  final String? title;

  /// 可选抽屉副标题。
  final String? subtitle;

  /// 标题栏右侧操作组件。
  final Widget? trailing;

  /// 抽屉主体内容。
  final Widget child;

  /// 拖拽指示条尺寸。
  static const double _handleWidth = 36;
  static const double _handleHeight = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final headerTitle = title;
    final headerSubtitle = subtitle;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LexiLayout.readingMaxWidth,
          ),
          child: Container(
            margin: const EdgeInsets.all(LexiSpace.s12),
            padding: const EdgeInsets.fromLTRB(
              LexiSpace.s20,
              LexiSpace.s12,
              LexiSpace.s20,
              LexiSpace.s20,
            ),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(LexiRadius.xxl),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: _handleWidth,
                    height: _handleHeight,
                    decoration: BoxDecoration(
                      color: colors.separator,
                      borderRadius: BorderRadius.circular(LexiRadius.pill),
                    ),
                  ),
                ),
                if (headerTitle != null) ...<Widget>[
                  const SizedBox(height: LexiSpace.s12),
                  _SheetHeader(
                    title: headerTitle,
                    subtitle: headerSubtitle,
                    trailing: trailing,
                  ),
                  const SizedBox(height: LexiSpace.s12),
                ] else
                  const SizedBox(height: LexiSpace.s8),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const new({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final sub = subtitle;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: LexiType.title.copyWith(color: colors.label)),
              if (sub != null && sub.isNotEmpty) ...<Widget>[
                const SizedBox(height: LexiSpace.s2),
                Text(
                  sub,
                  style: LexiType.caption.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
