/// 粘贴文章 · AI 选词导词页。
///
/// 对应旧版 `src/components/add/article-tab.tsx`（1115 行）的三步交互：
/// 粘贴 → 分段预览 / 勾选 / 合并 → 提交。旧版是「添加词条」页里的一个标签页；
/// 本版做成顶层路由（`/article`，与 CSV 导入同规格），因为它是一个多步向导，
/// 套在外壳里会让用户在流程中途被导航分散注意力。
///
/// **与旧版的差异（有意）**：不逐行照搬 DOM，而是还原用户可见的状态机——
/// 步骤切换、分段增量展示、AI 回退提示与重试入口、勾选与提交的可用性。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_input_step.dart';
import 'package:lexiloop/features/add/widgets/article_preview_step.dart';
import 'package:lexiloop/features/add/widgets/article_progress_step.dart';
import 'package:lexiloop/features/add/widgets/article_success_card.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/adaptive_columns.dart';
import 'package:lexiloop/ui/widgets/flow_steps.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 页内边距。
const double articlePagePadding = 20;

/// 底部留白。
const double articlePageBottomPadding = 40;

/// 粘贴文章页。
class ArticlePage extends ConsumerStatefulWidget {
  /// 创建粘贴文章页。
  const new({super.key});

  @override
  ConsumerState<ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends ConsumerState<ArticlePage> {
  @override
  void initState() {
    super.initState();
    // 用 post-frame 回调而不是在 build 里读设置：build 期间改 provider 状态
    // 会触发 Riverpod 的「构建中修改」断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(articleWizardProvider.notifier).loadExamTargets());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(articleWizardProvider);
    // **不再自己画 `AmbientBackground`**：外壳统一画一次。
    return PageShell(
      scrollable: true,
      header: PageHeader(
        title: '文章提词',
        subtitle: '粘贴英文，挑选词汇，预览后导入。',
        leading: Builder(
          builder: (backContext) => IconButton(
            key: const Key('articleBack'),
            tooltip: '返回',
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => backContext.go(addWordPath),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FlowSteps(
            labels: const <String>['输入文章', '分析选词', '确认导入', '完成'],
            current: switch (state.analysis.step) {
              ArticleStep.input => 0,
              ArticleStep.analyzing => 1,
              ArticleStep.preview || ArticleStep.committing => 2,
              ArticleStep.success => 3,
            },
          ),
          _bodyFor(state),
        ],
      ),
    );
  }

  Widget _bodyFor(ArticleWizardState state) => switch (state.analysis.step) {
    ArticleStep.input => const ArticleInputStep(),
    ArticleStep.analyzing => const ArticleProgressStep(),
    ArticleStep.preview => AdaptiveColumns(
      primary: const ArticlePreviewStep(),
      secondary: SectionCard(
        title: '原文',
        child: SelectableText(state.draft.text, style: LexiType.body),
      ),
    ),
    ArticleStep.committing => const ArticleCommittingStep(),
    ArticleStep.success => ArticleSuccessCard(result: state.result!),
  };
}
