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
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

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
///
/// **必须有第二个出口**：学习页是沉浸路由——窄屏下外壳连底部 Tab Bar
/// 都不渲染，全应用也没有一处 `PopScope`。于是「加载失败」曾经是一个
/// 真正的死胡同：能点的只有「重试」，如果失败原因是持久的（词条数据损坏、
/// 库被占用），用户只能杀掉应用。这不是理论问题，它是同一份代码里
/// 上一个空态页被修掉的原因（见文件头注释），只是错误态漏了。
class StudyErrorView extends StatelessWidget {
  /// 以错误文案、重试回调与退出回调构造。
  const new({
    required this.message,
    required this.onRetry,
    required this.onExit,
    this.exitLabel = '返回首页',
    super.key,
  });

  /// 面向用户的错误文案。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  /// 离开本页的回调；沉浸路由上这是唯一的退路，因此必填。
  final VoidCallback onExit;

  /// 退出按钮的文案。
  final String exitLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LexiSpace.s32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 40, color: colors.danger),
            const SizedBox(height: LexiSpace.s12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: LexiSpace.s14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: studyButtonHeight,
                    minWidth: 120,
                  ),
                  child: OutlinedButton(
                    onPressed: onExit,
                    child: Text(exitLabel),
                  ),
                ),
                const SizedBox(width: LexiSpace.s12),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: studyButtonHeight,
                    minWidth: 120,
                  ),
                  child: FilledButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
