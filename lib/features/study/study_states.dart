/// 学习会话的加载态与错误态。
///
/// 两种状态都是**整页**呈现，与「有题可做」的主体互斥，因此单独成文件：
/// 主体只需要关心一道路径清晰的作答流程。
///
/// **这里没有空态**：「今天没词可学」走的是 `StudySummaryView`（标题不同），
/// 因为对用户来说它与「刚做完一轮」是同一件事，旧版
/// `study-client.tsx:548` 也是同一个分支。曾有一个独立的空态页，
/// 它只剩一个 `maybePop` 的返回按钮——在分支根路由上点了没反应，
/// 把用户困在沉浸式页面里。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 加载态。
class StudyLoadingView extends StatelessWidget {
  /// 创建加载态。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// 错误态。
class StudyErrorView extends StatelessWidget {
  /// 以错误文案与重试回调构造。
  const new({required this.message, required this.onRetry, super.key});

  /// 面向用户的错误文案。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 40, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: studyButtonHeight,
                minWidth: 120,
              ),
              child: FilledButton(onPressed: onRetry, child: const Text('重试')),
            ),
          ],
        ),
      ),
    );
  }
}
