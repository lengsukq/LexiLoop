/// 页面页头：标题、副标题、返回与动作，全应用唯一一种写法。
///
/// **为什么必须统一**：收敛前「页头」这件事有 7 种实现——今日页是
/// `LexiType.display` + 品牌副标题，单词本是 `LexiType.page` + 计数，
/// 统计页是 `page` + 刷新按钮，设置页是居中标题 + 一行「所有改动即时生效」
/// 的承诺，添加页是 `headlineSmall`，导入页是 `page` + 三步说明，
/// 词条详情页干脆没有标题（只有一张卡片）。同一个应用里
/// 「页面标题」有 4 种字号、3 种对齐、2 种副标题语义。
///
/// 统一后只有一条规则：**`title` 一律 `LexiType.page`，`subtitle` 一律
/// 一句话说明本页能做什么**（不是产品口号，不是实现细节）。
///
/// **动作会溢出的地方自动收进菜单**：词条详情页曾经把「补全 / 有道词典 /
/// 编辑 / 重新生成 / 删除」五个文字按钮平铺在标题右侧，删除与重新生成
/// 相隔约 40 像素。本构件默认只平铺两个动作，
/// 其余进「⋯」菜单——把危险动作从一等位置降下来，是布局问题，
/// 也是安全问题。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 页头上的一个动作。
///
/// **文案一直显示，图标只是辅助**：图标按钮在页头里很省地方，但一个
/// 只有图标的「刷新」要靠悬停提示才认得出，而 macOS 上鼠标恰好停在按钮上
/// 这件事没人能保证。所以带图标时渲染的是「图标 + 文字」，
/// 只有 [label] 为空才退化成纯图标按钮。
@immutable
class PageHeaderAction {
  /// 以文案与回调构造。
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.primary = false,
    this.key,
  });

  /// 按钮文案；为空时渲染成纯图标按钮（此时 [icon] 必填）。
  final String label;

  /// 触发回调。
  final VoidCallback onPressed;

  /// 可选图标。
  final IconData? icon;

  /// 是否为破坏性动作（用危险色，且在溢出菜单里排最后）。
  final bool destructive;

  /// 是否为该页的主按钮（填充底）。
  final bool primary;

  /// 供测试定位；页头动作会在按钮本体上挂这个 key。
  final Key? key;
}

/// 一键返回：能出栈就出栈，否则跳到 [fallbackLocation]。
///
/// **为什么是一个函数而不是工厂构造**：它必须读到 [BuildContext] 才能
/// 判断「能不能出栈」，而这个判断只有在点击那一刻才准确。写成
/// `PageHeaderAction.back(context, fallbackLocation: …)` 与其它动作用同一种
/// 调用形状，页头那一行读起来就是「平铺了哪些动作」。
///
/// **为什么需要兜底**：`context.pop()` 在没有上一页时会抛异常，而
/// `Navigator.maybePop()` 在 `context.go` 进入的页面上是空操作——
/// 词条详情页的「返回」按钮曾经两者都用过，结果按钮可能什么都不做。
/// 这里把两种情况显式分开。
PageHeaderAction backAction(
  BuildContext context, {
  required String fallbackLocation,
  String label = '返回',
}) => PageHeaderAction(
  label: label,
  icon: LucideIcons.arrowLeft,
  onPressed: () {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  },
);

/// 返回按钮（`leading` 用）。
///
/// 与 [backAction] 同源：页头右侧的动作区要 `PageHeaderAction`，
/// 而左侧的 `leading` 要一个 `Widget`——同一个「返回」在两处的形状不同，
/// 但行为必须一致，所以这里也走「能出栈就出栈，否则回兜底位置」。
/// 返回按钮（`leading` 用）。
///
/// [preferPop] 为 `true` 时「能出栈就出栈」，适合被推入栈内的页面（词条详情）。
/// 用在**导航外壳的分支目的地**上时必须传 `false`：`StatefulShellRoute` 的
/// 分支里 `context.canPop()` 会返回 `true`，但 `pop()` 弹掉的是分支导航器中
/// 那个与当前页相同的条目——位置不变、界面不动，用户会觉得按钮坏了。
Widget backButton(
  BuildContext context, {
  required String fallbackLocation,
  String tooltip = '返回',
  bool preferPop = true,
}) => IconButton(
  key: const Key('pageHeaderBack'),
  tooltip: tooltip,
  icon: const Icon(LucideIcons.arrowLeft),
  onPressed: () {
    if (preferPop && context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackLocation);
    }
  },
);

/// 统一页头。
class PageHeader extends StatelessWidget {
  /// 以标题、可选副标题、可选返回与动作构造。
  const new({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <PageHeaderAction>[],
    this.bottom,
    this.trailing,
    super.key,
  });

  /// 标题。
  final String title;

  /// 副标题：一句话说明本页做什么。
  final String? subtitle;

  /// 标题左侧的前导构件（通常是返回按钮）。
  final Widget? leading;

  /// 右侧动作；超过 [visibleActionCount] 个时余下进「⋯」菜单。
  final List<PageHeaderAction> actions;

  /// 页头下方的附加内容（步骤指示器、区间选择器等）。
  final Widget? bottom;

  /// 动作之后的自定义控件。
  ///
  /// 给「自带状态、不能压成一条 [PageHeaderAction]」的入口留的位置：
  /// 词库页的「导入备份」在导入过程中要显示转圈，压成纯动作就丢了那个
  /// 状态。它排在动作之后、「⋯」之前，视觉上仍属于动作区。
  final Widget? trailing;

  /// 直接平铺的动作个数上限。
  static const int visibleActionCount = 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // **窄窗口下动作换行，而不是把标题挤扁**。
        //
        // 收敛前这里是一条 Row：标题用 Expanded、动作跟在后面。360 宽下
        // 「手动添加 + CSV 导入 + 导入备份」三个入口就把整行撑爆
        // （`RenderFlex overflowed by 84 pixels`）——标题被压到几乎读不出，
        // 按钮还溢出到屏幕外。宽度不够时把动作挪到第二行，是本该有的行为。
        final narrow = constraints.maxWidth < compactHeaderWidth;
        final titleRow = _titleRow(colors);
        // 窄屏只平铺**一个**动作，其余进「⋯」：360 宽下平铺两个动作 + 一个
        // trailing 会把页头摞成三行（标题一行、按钮两行），页头本身吃掉
        // 三分之一屏。平铺一个主按钮 + 一个「⋯」既保住了主线动作，
        // 又让页头回到两行。
        final actionsRow = _actionWidgets(
          colors,
          inline: narrow ? 1 : visibleActionCount,
        );
        if (!narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: titleRow),
                  ...actionsRow,
                ],
              ),
              ..._bottomSlot(),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            titleRow,
            if (actionsRow.isNotEmpty) ...<Widget>[
              const SizedBox(height: LexiSpace.s10),
              // Wrap 而不是 Row：动作自己也放不下时继续折行。
              Wrap(
                spacing: LexiSpace.s8,
                runSpacing: LexiSpace.s8,
                children: actionsRow,
              ),
            ],
            ..._bottomSlot(),
          ],
        );
      },
    );
  }

  /// 标题与副标题（含前导按钮）。
  Widget _titleRow(LexiColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: LexiSpace.s8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: LexiType.page.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: LexiSpace.s4),
                Text(
                  subtitle!,
                  style: LexiType.body.copyWith(color: colors.secondaryLabel),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 动作区：平铺的前两个 + 自定义 trailing + 「⋯」。
  List<Widget> _actionWidgets(LexiColors colors, {required int inline}) {
    final visible = actions.take(inline).toList(growable: false);
    final overflow = actions.skip(inline).toList(growable: false);
    return <Widget>[
      for (final action in visible) _ActionButton(action: action),
      ?trailing,
      if (overflow.isNotEmpty) _OverflowMenu(actions: overflow, colors: colors),
    ];
  }

  List<Widget> _bottomSlot() {
    final slot = bottom;
    if (slot == null) return const <Widget>[];
    return <Widget>[const SizedBox(height: LexiSpace.s14), slot];
  }
}

/// 页头从「单行」切到「标题 + 动作两行」的宽度阈值。
///
/// 480 的依据：手机竖屏 360–430 一律两行；平板与桌面单行。
const double compactHeaderWidth = 480;

/// 平铺的动作按钮。
class _ActionButton extends StatelessWidget {
  const new({required this.action});

  final PageHeaderAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = action.destructive
        ? colors.dangerText
        : colors.accentText;
    final icon = action.icon;

    // 纯图标：只有调用方明确不给文案时才用，并提供悬停提示兜底。
    if (action.label.isEmpty) {
      return Tooltip(
        message: action.label,
        child: IconButton(
          key: action.key,
          onPressed: action.onPressed,
          icon: Icon(icon, size: _actionIconSize, color: foreground),
        ),
      );
    }

    final style = action.destructive
        ? TextButton.styleFrom(foregroundColor: colors.dangerText)
        : null;

    if (icon == null) {
      return action.primary
          ? FilledButton(
              key: action.key,
              onPressed: action.onPressed,
              child: Text(action.label),
            )
          : TextButton(
              key: action.key,
              onPressed: action.onPressed,
              style: style,
              child: Text(action.label),
            );
    }

    return action.primary
        ? FilledButton.icon(
            key: action.key,
            onPressed: action.onPressed,
            icon: Icon(icon, size: _actionIconSize),
            label: Text(action.label),
          )
        : TextButton.icon(
            key: action.key,
            onPressed: action.onPressed,
            style: style,
            icon: Icon(icon, size: _actionIconSize, color: foreground),
            label: Text(action.label),
          );
  }
}

/// 动作溢出菜单。
class _OverflowMenu extends StatelessWidget {
  const new({required this.actions, required this.colors});

  final List<PageHeaderAction> actions;
  final LexiColors colors;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PageHeaderAction>(
      tooltip: '更多操作',
      icon: Icon(LucideIcons.ellipsis, color: colors.secondaryLabel),
      onSelected: (action) => action.onPressed(),
      itemBuilder: (context) => <PopupMenuEntry<PageHeaderAction>>[
        for (final action in actions)
          PopupMenuItem<PageHeaderAction>(
            value: action,
            child: Row(
              children: <Widget>[
                if (action.icon != null) ...<Widget>[
                  Icon(
                    action.icon,
                    size: _actionIconSize,
                    color: action.destructive
                        ? colors.dangerText
                        : colors.label,
                  ),
                  const SizedBox(width: LexiSpace.s10),
                ],
                Text(
                  action.label,
                  style: LexiType.callout.copyWith(
                    color: action.destructive
                        ? colors.dangerText
                        : colors.label,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 页头动作图标的尺寸。
const double _actionIconSize = 18;
