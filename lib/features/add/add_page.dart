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
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 添加词条页。
class AddPage extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) => AmbientBackground(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          pagePadding,
          pagePadding,
          pagePadding,
          pagePaddingBottom,
        ),
        children: <Widget>[
          Text(
            '添加词条',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: context.lexiColors.label),
          ),
          const SizedBox(height: subtitleGap),
          Text(
            <String>[
              '手动填写词条与释义直接入库（离线可用）；',
              '也可以贴一批词，先查词典生成预览，逐行确认后再入库。',
            ].join(),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: context.lexiColors.tertiaryLabel),
          ),
          const SizedBox(height: sectionGap),
          const _ArticleImportCard(),
          const SizedBox(height: sectionGap),
          const _ManualSection(),
        ],
      ),
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
              icon: Icon(Icons.edit_note_rounded, size: 16),
              label: Text('手动填写'),
            ),
            ButtonSegment<ManualAddMode>(
              value: ManualAddMode.batch,
              icon: Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text('词典批量预览'),
            ),
          ],
          selected: <ManualAddMode>{_mode},
          onSelectionChanged: (selection) =>
              setState(() => _mode = selection.first),
        ),
        const SizedBox(height: sectionGap),
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

/// 「粘贴文章」入口的说明文案。
///
/// 用 `join()` 而不是相邻字符串字面量：中文文案之间不需要空格，而相邻字面量
/// 的「缺空格」会被 `missing_whitespace_between_adjacent_strings` 判为笔误。
final String _articleImportHint = <String>[
  '粘贴一篇英文文章，AI 会结合你的词库与考试目标挑出值得学的',
  '单词、短语与句子；长文可分段并发分析，边解析边勾选。',
].join();

/// 「粘贴文章」入口卡片。
///
/// 整条链路（粘贴 → 分段预览 → 勾选 → 提交）是一个多步向导，因此进入
/// 顶层路由 `/article`，而不是在本页内联展开。
class _ArticleImportCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_rounded, color: colors.accent, size: 20),
              const SizedBox(width: iconGap),
              Text(
                '粘贴文章 · AI 选词导词',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: colors.label),
              ),
            ],
          ),
          const SizedBox(height: itemGap),
          Text(
            _articleImportHint,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: actionGap),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('addOpenArticleImport'),
              onPressed: () => context.go(articlePath),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('开始粘贴'),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, color: colors.success, size: 20),
              const SizedBox(width: iconGap),
              Text(
                '已添加到词库',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: colors.label),
              ),
            ],
          ),
          const SizedBox(height: itemGap),
          Text(
            '词条 ID：$wordId。可以在「词库」里找到它。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: actionGap),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: onAddAnother,
              child: const Text('继续添加'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 页面内边距。
const double pagePadding = 20;

/// 底部留白。
const double pagePaddingBottom = 96;

/// 标题与副标题的间距。
const double subtitleGap = 6;

/// 分节间距。
const double sectionGap = 16;

/// 卡片内边距。
const double cardPadding = 16;

/// 图标与文本的间距。
const double iconGap = 8;

/// 行间距。
const double itemGap = 6;

/// 正文与按钮的间距。
const double actionGap = 14;
