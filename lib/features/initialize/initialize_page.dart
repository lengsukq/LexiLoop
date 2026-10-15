/// 初始化队列页。
///
/// 对应旧版 `app/(main)/initialize/page.tsx`。
///
/// **职责边界**：这一页是**监控与补救**入口——词条由 CSV 导入、手动添加
/// 或词典补全自动入队，用户在这里看进度、取消误入队的任务、重试失败的。
/// 旧版把「配置数据源 + 选词 + 进度 + 任务详情」全塞进一个页面，
/// 这里拆成「进度概览 / 筛选 / 列表 / 行内操作」四个组件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/initialize/widgets/queue_bulk_bar.dart';
import 'package:lexiloop/features/initialize/widgets/queue_list.dart';
import 'package:lexiloop/features/initialize/widgets/queue_progress_card.dart';
import 'package:lexiloop/features/initialize/widgets/queue_toolbar.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 初始化队列页。
class InitializePage extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const AmbientBackground(
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            _PageBody(),
            // 浮条压在列表之上：多选条要跟着视线出现在底部，
            // 而不是把列表往下推（那会让刚选中的行离开视野）。
            Align(alignment: Alignment.bottomCenter, child: QueueBulkBar()),
          ],
        ),
      ),
    );
  }
}

/// 页头、概览、工具栏与列表。
///
/// 拆成独立控件是为了守住 `build()` 的 80 行上限：这一页还在长，
/// 每一块内容都应该能单独换掉而不动骨架。
class _PageBody extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        pagePadding,
        pagePadding,
        pagePadding,
        pagePaddingBottom,
      ),
      children: <Widget>[
        Text(
          '初始化队列',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: context.lexiColors.label),
        ),
        const SizedBox(height: subtitleGap),
        Text(
          '词条导入后会排队补全释义、音标、例句等字段。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.tertiaryLabel),
        ),
        const SizedBox(height: sectionGap),
        const QueueProgressCard(),
        const SizedBox(height: sectionGap),
        const QueueToolbar(),
        const SizedBox(height: itemGap),
        const QueueList(),
      ],
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

/// 工具栏与列表的间距。
const double itemGap = 10;
