/// 页面的「空」与「失败」两种状态：全应用唯一一种写法。
///
/// **为什么必须统一**：收敛前这两种状态是四处漏的——
///
/// * 失败态：`ErrorRetryView` 只有 3 处调用（设置 / 词库 / 词条详情），
///   统计页 6 张卡片各自内联一段红字且**没有重试**，添加 / 导入 / 文章
///   三条流程各自抄了一份错误横幅，词条详情页的「初始化质量卡」还有
///   第四份；
/// * 空态：只有词库页写得齐全（加载 + 失败 + 空），统计页 5/6 张卡片有
///   空态但没有下一步，初始化队列的空态只有一行居中文字，
///   学习页的错误态**连出口都没有**——它在沉浸路由上，底部 Tab 被隐藏，
///   用户只能杀进程。
///
/// 所以这里的规则不是「长得一样」，而是**每个状态都必须给出下一步**：
/// 失败给「重试」+ 可选的第二出口，空态给「做点什么」的主按钮。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 空态与失败态的外边距。
const EdgeInsets _statePadding = EdgeInsets.all(LexiSpace.s32);

/// 状态图标的尺寸。
const double _stateIconSize = 40;

/// 图标与标题之间的间距。
const double _stateIconGap = LexiSpace.s12;

/// 标题与正文之间的间距。
const double _stateTextGap = LexiSpace.s6;

/// 正文与动作之间的间距。
const double _stateActionGap = LexiSpace.s16;

/// 空状态的图标底色直径。
const double _emptyIconPlateSize = 72;

/// 居中的空状态：说明「这里为什么是空的」并给出第一步。
class PageEmptyState extends StatelessWidget {
  /// 以图标、标题、说明与可选动作构造。
  const new({
    required this.title,
    required this.message,
    this.icon = LucideIcons.inbox,
    this.primaryLabel,
    this.onPrimary,
    this.primaryKey,
    this.iconColor,
    super.key,
  });

  /// 一句话标题，例如「还没有词条」。
  final String title;

  /// 说明：为什么是空的、下一步做什么。
  final String message;

  /// 图标。
  final IconData icon;

  /// 主按钮文案；为空时只显示文字。
  final String? primaryLabel;

  /// 主按钮回调。
  final VoidCallback? onPrimary;

  /// 主按钮的 key，供测试定位。
  final Key? primaryKey;

  /// 图标颜色；默认取强调色。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final accent = iconColor ?? colors.accent;
    return Center(
      child: Padding(
        padding: _statePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: LexiTint.tint),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: _emptyIconPlateSize,
                height: _emptyIconPlateSize,
                child: Icon(icon, size: _stateIconSize, color: accent),
              ),
            ),
            const SizedBox(height: _stateIconGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: LexiType.title.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: _stateTextGap),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            if (primaryLabel != null && onPrimary != null) ...<Widget>[
              const SizedBox(height: _stateActionGap),
              FilledButton(
                key: primaryKey,
                onPressed: onPrimary,
                child: Text(primaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 居中的失败态：原因 + 重试 + 可选的第二出口。
///
/// **第二出口不是可选项而是必需项**：只要这个失败态出现在沉浸路由
/// （学习 / 游戏 / 配对 / 音标）或顶层路由（导入 / 文章）上，用户就没有
/// 导航外壳可以依赖。调用方应当在那些页面上传 [secondaryLabel]。
class PageErrorState extends StatelessWidget {
  /// 以原因、重试回调与可选第二出口构造。
  const new({
    required this.message,
    required this.onRetry,
    this.title = '加载失败',
    this.details,
    this.secondaryLabel,
    this.onSecondary,
    this.retryLabel = '重试',
    super.key,
  });

  /// 面向用户的失败原因（已是中文）。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  /// 标题。
  final String title;

  /// 技术细节（HTTP 状态、原始报文等）。
  ///
  /// **默认折叠**：初始化队列曾经把 `HTTP 422 {"error":{"message":…}}`
  /// 整段当正文显示在词条行里，用户读到的是一串 JSON。技术细节要可查，
  /// 但不能是用户读到的第一句话。
  final String? details;

  /// 第二出口的文案，例如「返回首页」。
  final String? secondaryLabel;

  /// 第二出口的回调。
  final VoidCallback? onSecondary;

  /// 重试按钮的文案。
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: _statePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              LucideIcons.circleAlert,
              size: _stateIconSize,
              color: colors.danger,
            ),
            const SizedBox(height: _stateIconGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: LexiType.title.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: _stateTextGap),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            if (details != null) ...<Widget>[
              const SizedBox(height: _stateTextGap),
              _Details(details: details!, colors: colors),
            ],
            const SizedBox(height: _stateActionGap),
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
                FilledButton(onPressed: onRetry, child: Text(retryLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 可展开的技术细节。
class _Details extends StatelessWidget {
  const new({required this.details, required this.colors});

  final String details;
  final LexiColors colors;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            '技术细节',
            style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
          ),
          children: <Widget>[
            SelectableText(
              details,
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
