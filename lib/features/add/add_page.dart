/// 添加词条页。
///
/// 对应旧版 `app/(main)/add/page.tsx` 的「手动添加」标签页。
///
/// **与旧版的差异（一）**：旧版先调词典生成预览、确认后才落库，预览存在
/// 服务端 `manual_previews` 表里。本版把「手动录入」做成**不依赖网络**的
/// 路径——用户自己填释义即可建词条；需要词典补全时走初始化任务队列。
/// 这样离线可用，也不需要为单用户场景维护预览令牌与 TTL。
///
/// **与旧版的差异（二）**：旧版把「离线手填」与「词典批量预览」叠在同一个
/// 标签页里（文本域在上、批量结果在下）。本版改成**分段切换**：离线表单是
/// 一个 7 字段的完整表单，批量预览是一个多行文本域 + 逐行卡片，两者都有
/// 自己的提交按钮；叠在一起会出现「这个按钮提交的是哪一块」的歧义，页面也会
/// 长到需要来回滚动。分段切换让每条路径各自完整，且默认停在离线路径上——
/// 那是不依赖网络的那一条。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/add/add_providers.dart';
import 'package:lexiloop/features/add/widgets/manual_batch_panel.dart';
import 'package:lexiloop/features/add/widgets/manual_entry_form.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/adaptive_columns.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 添加词条页。
class AddPage extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) => PageShell(
    scrollable: true,
    // 表单页收窄到阅读列宽：铺满 1040 时，输入框、分段控件都长到
    // 一眼看不完，而字段内容只有几个字。与设置页同一个宽度。
    header: PageHeader(
      title: '添加词条',
      subtitle: '手动录入，或从已有内容导入。',
      leading: backButton(
        context,
        fallbackLocation: wordsPath,
        tooltip: '返回单词本',
      ),
    ),
    child: const AdaptiveColumns(
      primary: _ManualSection(),
      secondary: _ArticleImportCard(),
    ),
  );
}

/// 手动添加的两种模式。
enum ManualAddMode {
  /// 离线手填：不依赖网络，弱网 / 无网络时唯一能建词条的入口。
  offline,

  /// 词典批量预览：先查词典生成预览，逐行确认后才入库。
  batch,
}

/// 「手动填写 / 词典批量预览」的分段切换与对应内容。
class _ManualSection extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ManualSection> createState() => _ManualSectionState();
}

class _ManualSectionState extends ConsumerState<_ManualSection> {
  ManualAddMode _mode = ManualAddMode.offline;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualEntryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<ManualAddMode>(
          segments: const <ButtonSegment<ManualAddMode>>[
            ButtonSegment<ManualAddMode>(
              value: ManualAddMode.offline,
              icon: Icon(LucideIcons.notebookPen, size: 16),
              label: Text('手动填写'),
            ),
            ButtonSegment<ManualAddMode>(
              value: ManualAddMode.batch,
              icon: Icon(LucideIcons.sparkles, size: 16),
              label: Text('词典批量预览'),
            ),
          ],
          selected: <ManualAddMode>{_mode},
          onSelectionChanged: (selection) =>
              setState(() => _mode = selection.first),
        ),
        const SizedBox(height: LexiSpace.s16),
        if (_mode == ManualAddMode.batch)
          const ManualBatchPanel()
        else if (state.isCreated)
          _CreatedCard(
            wordId: state.createdWordId!,
            onAddAnother: () => ref.read(manualEntryProvider.notifier).reset(),
          )
        else
          const ManualEntryForm(),
      ],
    );
  }
}

/// 「粘贴文章」入口卡片。
///
/// 整条链路（粘贴 → 分段预览 → 勾选 → 提交）是一个多步向导，因此进入
/// 顶层路由 `/article`，而不是在本页内联展开。
class _ArticleImportCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '从已有内容导入',
          style: LexiType.title.copyWith(color: context.lexiColors.label),
        ),
        const SizedBox(height: LexiSpace.s12),
        Surface(
          variant: SurfaceVariant.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                LucideIcons.fileText,
                color: context.lexiTones.styleOf(LexiTone.lavender).foreground,
              ),
              const SizedBox(height: LexiSpace.s12),
              const Text('从文章提取词汇', style: LexiType.callout),
              const SizedBox(height: LexiSpace.s4),
              const Text('分析英文文章，预览后加入词库。', style: LexiType.footnote),
              TextButton(
                key: const Key('addOpenArticleImport'),
                onPressed: () => context.go(articlePath),
                child: const Text('开始粘贴'),
              ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s16),
        Surface(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              LucideIcons.fileSpreadsheet,
              color: context.lexiColors.accentText,
            ),
            title: const Text('导入 CSV 词库'),
            subtitle: const Text('从 EasyDict 收藏建立词库。'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => context.go(csvImportPath),
          ),
        ),
      ],
    );
  }
}

/// 创建成功后的回执卡片。
class _CreatedCard extends StatelessWidget {
  const new({required this.wordId, required this.onAddAnother});

  final int wordId;
  final VoidCallback onAddAnother;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(LexiSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LucideIcons.circleCheck, color: colors.success, size: 20),
              const SizedBox(width: LexiSpace.s8),
              Text(
                '已添加到词库',
                style: LexiType.title.copyWith(color: colors.label),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s6),
          Text(
            '词条已加入单词本，可在「单词本」中查看或补充例句。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s14),
          Wrap(
            spacing: LexiSpace.s10,
            runSpacing: LexiSpace.s8,
            children: <Widget>[
              FilledButton(
                onPressed: onAddAnother,
                child: const Text('继续添加'),
              ),
              OutlinedButton(
                onPressed: () => context.go('$wordDetailPathPrefix$wordId'),
                child: const Text('查看词条'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
