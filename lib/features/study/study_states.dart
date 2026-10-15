/// 学习会话的加载态、空态与错误态。
///
/// 三种状态都是**整页**呈现，与「有题可做」的主体互斥，因此单独成文件：
/// 主体只需要关心一道路径清晰的作答流程。
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

/// 空态：今日没有可学的词条。
class StudyEmptyView extends StatelessWidget {
  /// 以返回回调构造。
  const new({required this.onExit, super.key});

  /// 返回回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 44,
              color: colors.tertiaryLabel,
            ),
            const SizedBox(height: 14),
            Text(
              '今天没有需要复习的词了',
              style: TextStyle(
                color: colors.label,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '可以先去单词本导入或添加词条',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: studyButtonHeight,
                minWidth: 120,
              ),
              child: FilledButton(onPressed: onExit, child: const Text('返回')),
            ),
          ],
        ),
      ),
    );
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
