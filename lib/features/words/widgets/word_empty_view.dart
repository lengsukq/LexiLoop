/// 词库列表页的空状态。
///
/// 分两种文案：库里一个词条都没有时给「去导入」的下一步；
/// 有词条但被筛空了只提示「调整筛选」——这两种情况下按钮没有意义，
/// 给一个导入口反而会让人以为自己的词库空了。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/words/widgets/import_backup_button.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词库列表页的空状态。
class WordEmptyView extends ConsumerWidget {
  /// 以「是否已被筛选条件筛空」构造。
  const new({required this.filtered, super.key});

  /// 当前是否有生效中的关键词或筛选条件。
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **靠上对齐，不垂直居中**。
    //
    // 结果区是 `Expanded`，垂直居中会把这张空态卡推到页面下三分之二处：
    // 上面只剩搜索框和两行筛选，中间一大片空白，空态离它要解释的东西
    // （筛选条件）反而很远。留一段固定的上边距，让标题、筛选、空态连成一片。
    // **可滚动**：最小窗口（560 高）下这张空态卡比剩余空间还高
    // （`RenderFlex overflowed by 196 pixels on the bottom`）——
    // 图标 + 标题 + 说明 + 三个按钮叠起来放不进去。滚动而不是溢出：
    // 空间够时它看起来仍是静态的一屏，不够时用户能滚到按钮。
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s32,
        LexiSpace.s40,
        LexiSpace.s32,
        LexiSpace.s32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            LucideIcons.bookOpen,
            size: 44,
            color: context.lexiColors.tertiaryLabel,
          ),
          const SizedBox(height: LexiSpace.s14),
          Text(
            filtered ? '没有匹配的词条' : '还没有词条',
            style: LexiType.title.copyWith(
              color: context.lexiColors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s6),
          Text(
            filtered ? '调整筛选条件或清空搜索词后再试。' : '可以导入旧版备份，也可以直接用 CSV 导入建立词库。',
            textAlign: TextAlign.center,
            style: LexiType.body.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
          _EmptyActions(filtered: filtered),
        ],
      ),
    );
  }
}

/// 空态下方的一组动作。
///
/// 拆成独立控件有两个理由：`build()` 的 80 行上限；以及这块**分两种形态**
/// （库是空的 / 被筛空的），形态分支放在这里比埋在 `build()` 中段清楚。
class _EmptyActions extends ConsumerWidget {
  const new({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **被筛空时必须有一个「回到全部」的按钮**：文案此前写着
    // 「调整筛选条件或清空搜索词后再试」，却没有任何可点的东西——
    // 宽屏布局甚至没有「清除筛选」入口，用户在一条描述自己做不到
    // 的建议里打转。
    if (filtered) {
      return Padding(
        padding: const EdgeInsets.only(top: LexiSpace.s16),
        child: FilledButton.icon(
          key: const Key('wordsClearAll'),
          onPressed: () => ref.read(wordQueryProvider.notifier).clearAll(),
          icon: const Icon(LucideIcons.filterX, size: 17),
          label: const Text('清除全部筛选与搜索'),
        ),
      );
    }
    // **Wrap 而不是 Row**：这些按钮在 360 宽的手机上合起来比可用
    // 宽度还宽（`RenderFlex overflowed by 19 pixels`），Row 会把
    // 最后一个按钮挤出屏幕。Wrap 让它们在窄屏上折行。
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: LexiSpace.s8,
        runSpacing: LexiSpace.s8,
        children: <Widget>[
          // **先给「手动添加」**：空状态此前只导去两条批量导入路径，
          // 而「我只想加一个词看看」是最轻的第一次尝试。
          FilledButton.icon(
            onPressed: () => context.go(addWordPath),
            icon: const Icon(LucideIcons.plus, size: 17),
            label: const Text('手动添加'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go(csvImportPath),
            icon: const Icon(LucideIcons.upload, size: 17),
            label: const Text('CSV 导入'),
          ),
          const ImportBackupButton(),
        ],
      ),
    );
  }
}
