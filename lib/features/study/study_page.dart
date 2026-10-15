/// 学习会话页面。
///
/// 旧版 `study-client.tsx` 用 497 行把「取会话、按题型分支、作答、判题、
/// 自评、总结」塞进一个组件（见 `docs/CLEAN_CODE_BASELINE.md`）。这里按
/// 职责拆开：
///
/// - [StudyProgressHeader]：进度与计数，只读；
/// - [StudyPrompt]：题干，按题型分四种形态；
/// - [StudyAnswerArea]：作答控件，每个题型一个组件且自持草稿；
/// - [StudyRatingBar]：四档自评；
/// - [StudyFeedbackPanel] / [StudySummaryView]：判定反馈与会话总结；
/// - 本文件只保留「编排」：什么时候开始、什么时候提交、什么时候前进。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/features/study/study_answer.dart';
import 'package:lexiloop/features/study/study_feedback.dart';
import 'package:lexiloop/features/study/study_prompt.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_rating.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 学习会话页面。
///
/// 学习页在 `immersivePaths` 内，外壳不渲染导航，因此返回与进度条都由
/// 页面自己提供。
class StudyPage extends ConsumerWidget {
  /// 以学习模式创建页面。
  const new({required this.mode, super.key});

  /// 本次学习模式。
  final StudyMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(studySessionProvider);
    final accent =
        ref.watch(appSettingsProvider).value?.playback.defaultAccent ??
        Accent.us;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: session.when(
            loading: () =>
                StudySessionBody(mode: mode, session: null, accent: accent),
            error: (error, _) => StudyErrorView(
              message: studyErrorMessage(error),
              onRetry: () => _retry(ref),
            ),
            data: (view) =>
                StudySessionBody(mode: mode, session: view, accent: accent),
          ),
        ),
      ),
    );
  }

  void _retry(WidgetRef ref) {
    unawaited(ref.read(studySessionProvider.notifier).start(mode));
  }
}

/// 会话主体：持有作答草稿与判定反馈，编排各子组件。
class StudySessionBody extends ConsumerStatefulWidget {
  /// 以模式、会话与默认口音构造。
  const new({
    required this.mode,
    required this.session,
    required this.accent,
    super.key,
  });

  /// 本次学习模式（重试与「再来一轮」要用）。
  final StudyMode mode;

  /// 当前会话；尚未加载时为 `null`。
  final StudySessionView? session;

  /// 设置中的默认发音口音。
  final Accent accent;

  @override
  ConsumerState<StudySessionBody> createState() => _StudySessionBodyState();
}

class _StudySessionBodyState extends ConsumerState<StudySessionBody> {
  ReviewOutcome? _outcome;
  StudyItemView? _answered;
  String? _answer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 首帧之后再启动会话：initState 处于构建阶段，此时改 provider 状态会
    // 触发「构建期间修改 provider」的断言。
    if (widget.session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didUpdateWidget(covariant StudySessionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session?.id != oldWidget.session?.id) {
      _resetRound();
      return;
    }
    // 反馈展示期间当前题被冻结（见 _answered），草稿必须留着。
    if (_outcome != null) return;
    if (_itemIdOf(oldWidget.session) != _itemIdOf(widget.session)) {
      _answer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) return const StudyLoadingView();
    if (session.items.isEmpty) return StudyEmptyView(onExit: _exit);

    final item = _answered ?? session.currentItem;
    if (item == null) {
      return StudySummaryView(
        session: session,
        onRestart: _restart,
        onHome: _home,
      );
    }
    return Column(
      children: <Widget>[
        StudyProgressHeader(
          session: session,
          onSkip: _outcome == null && !_busy ? _skip : null,
          onExit: _exit,
        ),
        Expanded(child: _content(item)),
      ],
    );
  }

  Widget _content(StudyItemView item) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        StudyPrompt(item: item, accent: widget.accent),
        const SizedBox(height: 16),
        StudyAnswerArea(
          item: item,
          outcome: _outcome,
          onAnswer: _setAnswer,
          onSubmit: _submit,
        ),
        if (isObjectivelyScored(item.questionType)) ...<Widget>[
          const SizedBox(height: 16),
          SubmitButton(enabled: _canSubmit, busy: _busy, onSubmit: _submit),
        ],
        if (_showsRating(item)) ...<Widget>[
          const SizedBox(height: 20),
          StudyRatingBar(
            hint: _ratingHint,
            enabled: _outcome == null,
            selected: _outcome?.rating,
            onSelect: _selectRating,
          ),
        ],
        if (_outcome case final outcome?) ...<Widget>[
          const SizedBox(height: 16),
          StudyFeedbackPanel(outcome: outcome),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: FilledButton(onPressed: _next, child: const Text('下一题')),
          ),
        ],
      ],
    );
  }

  /// 是否展示四档自评。
  ///
  /// 客观题在**提交后**才展示：先作答、再自评是既定交互顺序，提交前让用户
  /// 给一道还不知道对错的题打自评等于让他猜。看词说义没有客观判定，
  /// 自评本身就是作答入口，因此提交前也要展示。
  bool _showsRating(StudyItemView item) =>
      _outcome != null || !isObjectivelyScored(item.questionType);

  String get _ratingHint => _outcome == null ? '你记得怎么样？' : '已记录的等级';

  StudyItemView? get _item => _answered ?? widget.session?.currentItem;

  bool get _canSubmit => !_busy && (_answer?.isNotEmpty ?? false);

  void _start() {
    if (!mounted) return;
    unawaited(ref.read(studySessionProvider.notifier).start(widget.mode));
  }

  void _setAnswer(String value) => setState(() => _answer = value);

  /// 提交客观题的作答。
  ///
  /// 自评固定为「记得」：客观题的对错由判题决定，答错时服务层会把「记得」
  /// 降级为「忘了」，选「模糊 / 简单」则保留用户判断。界面不重复这条规则。
  void _submit() => unawaited(_submitWith(ReviewRating.good));

  void _selectRating(ReviewRating rating) {
    if (_outcome != null) return;
    unawaited(_submitWith(rating));
  }

  Future<void> _submitWith(ReviewRating rating) async {
    final item = _item;
    if (item == null || _busy) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(studySessionProvider.notifier)
          .submit(rating: rating, userAnswer: _answer);
      if (!mounted || outcome == null) return;
      setState(() {
        _outcome = outcome;
        _answered = item;
      });
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(studyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(studySessionProvider.notifier).skip();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(studyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    setState(() {
      _outcome = null;
      _answered = null;
      _answer = null;
    });
  }

  void _restart() {
    _resetRound();
    _start();
  }

  void _resetRound() {
    _outcome = null;
    _answered = null;
    _answer = null;
  }

  int? _itemIdOf(StudySessionView? session) => session?.currentItem?.itemId;

  void _exit() => Navigator.maybePop(context);

  /// 返回首页。
  ///
  /// 学习页是分支根路由，`maybePop` 在根路由上什么也不会发生；路由器在场时
  /// 直接跳 `/`，测试等无路由器的场景再退回出栈。
  void _home() {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      Navigator.maybePop(context);
      return;
    }
    router.go('/');
  }
}

/// 顶部进度与计数。
class StudyProgressHeader extends StatelessWidget {
  /// 以会话、跳过回调（为空表示禁用）与结束回调构造。
  const new({
    required this.session,
    required this.onSkip,
    required this.onExit,
    super.key,
  });

  /// 当前会话。
  final StudySessionView session;

  /// 跳过回调；提交后为 `null`，此时按钮禁用。
  final VoidCallback? onSkip;

  /// 结束回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _CountsRow(session: session),
              const Spacer(),
              _HeaderAction(
                label: '跳过',
                enabled: onSkip != null,
                onTap: onSkip,
              ),
              _HeaderAction(label: '结束', enabled: true, onTap: onExit),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressTrack(
            value: session.plannedCount <= 0
                ? 0
                : session.completedCount / session.plannedCount,
          ),
        ],
      ),
    );
  }
}

/// 已完成 / 计划 与正确 / 错误计数。
class _CountsRow extends StatelessWidget {
  const new({required this.session});

  final StudySessionView session;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Text(
          '${session.completedCount} / ${session.plannedCount}',
          style: TextStyle(
            color: colors.label,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        _CountChip(
          label: '正确',
          value: session.correctCount,
          color: colors.success,
        ),
        const SizedBox(width: 6),
        _CountChip(
          label: '错误',
          value: session.wrongCount,
          color: colors.danger,
        ),
      ],
    );
  }
}

/// 单个计数胶囊。
class _CountChip extends StatelessWidget {
  const new({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 进度条。
class _ProgressTrack extends StatelessWidget {
  const new({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: colors.fill,
        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
      ),
    );
  }
}

/// 顶部的小动作按钮（跳过 / 结束）。
class _HeaderAction extends StatelessWidget {
  const new({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
      child: TextButton(
        onPressed: enabled ? onTap : null,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? colors.accent : colors.tertiaryLabel,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

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
              constraints: const BoxConstraints(minHeight: 46, minWidth: 120),
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
              constraints: const BoxConstraints(minHeight: 46, minWidth: 120),
              child: FilledButton(onPressed: onRetry, child: const Text('重试')),
            ),
          ],
        ),
      ),
    );
  }
}
