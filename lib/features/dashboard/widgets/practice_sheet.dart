/// 「全部练习」弹层。
///
/// **为什么是弹层而不是再把两组折叠行塞回首页**：首页的首屏属于今日计划，
/// 练习只该提供几条常用入口；把 11 项全部平铺会把建议与提醒推到更下面，
/// 而重新做成两条折叠行又回到了「单独挂在卡片外」的旧问题。弹层让全部入口
/// 共享一个分组结构，首页则保持一张干净的卡片。
///
/// 弹层走内容层的卡片材质（主题里的 `BottomSheetThemeData`），不使用玻璃：
/// 11 行文字需要稳定的阅读底，且这本来就是一张覆盖在页面上的可滚动列表。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/dashboard/practice_catalog.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 弹层根节点的 Key，供测试定位。
const Key practiceSheetKey = Key('practice-sheet');

/// 关闭按钮的 Key。
const Key practiceSheetCloseKey = Key('practice-sheet-close');

/// 「打开趣味训练页」的 Key。
const Key practiceOpenGamesKey = Key('practice-open-games');

/// 弹层最大宽度：宽窗口下不要拉成通栏。
const double practiceSheetMaxWidth = 560;

/// 弹层占屏幕高度的上限；再高会让用户忘记自己还在首页上。
const double _sheetMaxHeightFactor = 0.82;

/// 打开「全部练习」弹层。
Future<void> showPracticeSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: practiceSheetMaxWidth),
      builder: (context) => const PracticeSheet(),
    );

/// 全部练习弹层。
class PracticeSheet extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * _sheetMaxHeightFactor;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        key: practiceSheetKey,
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: const SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            LexiSpace.s16,
            0,
            LexiSpace.s16,
            LexiSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SheetHeader(),
              _PracticeGroups(),
              _SheetFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标题、说明与关闭。
class _SheetHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s4, bottom: LexiSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '全部练习',
                  style: LexiType.title.copyWith(color: colors.label),
                ),
                const SizedBox(height: LexiSpace.s2),
                Text(
                  '${practiceEntries.length} 项练习 · 不计入每日计划',
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: practiceSheetCloseKey,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, size: 18),
          ),
        ],
      ),
    );
  }
}

/// 三组入口。
class _PracticeGroups extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (
        var index = 0;
        index < practiceCategories.length;
        index++
      ) ...<Widget>[
        if (index > 0) const SizedBox(height: LexiSpace.s16),
        _GroupHeader(category: practiceCategories[index]),
        for (final entry in practiceCategories[index].entries)
          _PracticeRow(entry: entry),
      ],
    ],
  );
}

/// 一组入口的标题与数量。
class _GroupHeader extends StatelessWidget {
  const new({required this.category});

  final PracticeCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(left: LexiSpace.s8, bottom: LexiSpace.s4),
      child: Row(
        children: <Widget>[
          Icon(category.icon, size: 16, color: colors.secondaryLabel),
          const SizedBox(width: LexiSpace.s6),
          Expanded(
            child: Text(
              category.title,
              style: LexiType.footnote.copyWith(
                color: colors.secondaryLabel,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${category.entries.length} 项',
            style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 弹层里的一行入口。
class _PracticeRow extends StatelessWidget {
  const new({required this.entry});

  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tone = context.lexiTones.styleOf(LexiTone.lavender);
    final radius = BorderRadius.circular(LexiRadius.md);
    return InkWell(
      borderRadius: radius,
      onTap: () => _openPractice(context, entry.location),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s8,
          vertical: LexiSpace.s8,
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(LexiSpace.s8),
              decoration: BoxDecoration(
                color: tone.background,
                borderRadius: BorderRadius.circular(LexiRadius.sm),
              ),
              child: Icon(entry.icon, size: 18, color: tone.foreground),
            ),
            const SizedBox(width: LexiSpace.s12),
            Expanded(child: _PracticeRowText(entry: entry)),
            const SizedBox(width: LexiSpace.s8),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹层行里的标题与说明。
class _PracticeRowText extends StatelessWidget {
  const new({required this.entry});

  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          entry.label,
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s2),
        Text(
          entry.subtitle,
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 保留原来首页右上角「趣味训练」的出口。
class _SheetFooter extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LexiSpace.s8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: practiceOpenGamesKey,
        onPressed: () => _openPractice(context, '/games'),
        icon: const Icon(LucideIcons.gamepad2, size: 16),
        label: const Text('打开趣味训练页'),
      ),
    ),
  );
}

/// 先关弹层，再跳目标路由。
///
/// **先取 `GoRouter` 再 pop**：`pop` 之后弹层的 `context` 已经开始失效，
/// 那时再 `GoRouter.of(context)` 会读到已卸载的节点。
void _openPractice(BuildContext context, String location) {
  final router = GoRouter.of(context);
  Navigator.of(context).pop();
  router.go(location);
}
