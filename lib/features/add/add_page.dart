/// 添加词条页。
///
/// 对应旧版 `app/(main)/add/page.tsx` 的「手动添加」标签页。
///
/// **与旧版的差异**：旧版先调词典生成预览、确认后才落库，预览存在服务端
/// `manual_previews` 表里。本版把「手动录入」做成**不依赖网络**的路径——
/// 用户自己填释义即可建词条；需要词典补全时走初始化任务队列。
/// 这样离线可用，也不需要为单用户场景维护预览令牌与 TTL。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/add/add_providers.dart';
import 'package:lexiloop/features/add/widgets/manual_entry_form.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 添加词条页。
class AddPage extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manualEntryProvider);
    return AmbientBackground(
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
              '手动填写词条与释义，直接存入本地词库；需要词典补全时可稍后由初始化队列处理。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.lexiColors.tertiaryLabel),
            ),
            const SizedBox(height: sectionGap),
            if (state.isCreated)
              _CreatedCard(
                wordId: state.createdWordId!,
                onAddAnother: () =>
                    ref.read(manualEntryProvider.notifier).reset(),
              )
            else
              const ManualEntryForm(),
          ],
        ),
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
    return LiquidGlass(
      level: GlassLevel.elevated,
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
