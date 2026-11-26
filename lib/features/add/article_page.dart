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
import 'package:lexiloop/features/add/widgets/article_strategy_card.dart';
import 'package:lexiloop/features/add/widgets/article_success_card.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
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
        title: '文章智能分词',
        subtitle: '按难度智能分词并还原词形，导入后自动通过有道词典查词。',
        leading: Builder(
          builder: (backContext) => IconButton(
            key: const Key('articleBack'),
            tooltip: '返回',
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => backContext.go(addWordPath),
          ),
        ),
      ),
      bottomAction: state.analysis.step == ArticleStep.preview
          ? const _ArticleCommitBar()
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FlowSteps(
            labels: const <String>['输入文章', '智能分词', '确认导入', '完成'],
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

/// 预览步骤的吸底确认导入栏，避免长列表来回滚动寻找主按钮。
class _ArticleCommitBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final count = state.selection.selected.length;
    final canCommit = count > 0 && state.analysis.finalToken != null;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '已选 $count 个词条',
                style: LexiType.body.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '导入后自动交由有道词典查词与补全音标',
                style: LexiType.caption.copyWith(color: colors.secondaryLabel),
              ),
            ],
          ),
        ),
        const SizedBox(width: LexiSpace.s12),
        FilledButton.icon(
          key: const Key('articleCommit'),
          onPressed: canCommit
              ? () => commitArticleWithConfirm(context, notifier, state)
              : null,
          icon: const Icon(LucideIcons.arrowRight, size: 16),
          label: Text('确认导入 $count 个'),
        ),
      ],
    );
  }
}
