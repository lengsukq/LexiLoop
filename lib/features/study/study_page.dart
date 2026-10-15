/// 学习会话页面。
///
/// 旧版 `study-client.tsx` 用 497 行把「取会话、按题型分支、作答、判题、
/// 自评、总结」塞进一个组件（见 `docs/CLEAN_CODE_BASELINE.md`）。这里按
/// 职责拆开：
///
/// - [StudyProgressHeader]：进度与计数，只读；
/// - [StudyPrompt]：题干，按题型分四种形态；
/// - [StudyAnswerArea]：作答控件，每个题型一个组件且自持草稿；
/// - [StudyRatingBar]：四档自评，**同时是提交入口**；
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
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/features/study/study_progress_header.dart';
import 'package:lexiloop/features/study/study_prompt.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_rating.dart';
import 'package:lexiloop/features/study/study_states.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/glass.dart';

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
              // 只失效、不直接 `start`：失效后 `data(null)` 会让主体重建并
              // 在 initState 里启动，直接再调一次 start 会并发开出两个会话。
              onRetry: () => ref.invalidate(studySessionProvider),
            ),
            data: (view) =>
                StudySessionBody(mode: mode, session: view, accent: accent),
          ),
        ),
      ),
    );
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
        const SizedBox(height: 20),
        StudyRatingBar(
          hint: _ratingHint(item),
          enabled: _canRate(item),
          selected: _outcome?.rating,
          onSelect: _selectRating,
        ),
        if (_outcome case final outcome?) ...<Widget>[
          const SizedBox(height: 16),
          StudyFeedbackPanel(outcome: outcome),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: studyButtonHeight),
            child: FilledButton(onPressed: _next, child: const Text('下一题')),
          ),
        ],
      ],
    );
  }

  /// 四档自评的提示语。
  ///
  /// 三种状态对应三种文案：还没作答、可以自评、已经记录。
  String _ratingHint(StudyItemView item) {
    if (_outcome != null) return '已记录的等级';
    if (_awaitingAnswer(item)) return '先作答，再选择记得程度';
    return '你记得怎么样？';
  }

  /// 是否「客观题但还没给出作答」。
  ///
  /// 客观题需要用户先选出/拼出答案，自评按钮才可用；看词说义没有客观判定，
  /// 自评本身就是作答，因此立即可用。
  bool _awaitingAnswer(StudyItemView item) {
    if (!isObjectivelyScored(item.questionType)) return false;
    return _answer?.isNotEmpty != true;
  }

  StudyItemView? get _item => _answered ?? widget.session?.currentItem;

  /// 四档自评是否可点。
  ///
  /// **自评按钮就是提交按钮**：旧版的交互是「先作答，再选记得程度」，
  /// 选了即提交。所以这里不是「展示已记录等级」的只读控件。
  ///
  /// 提交后必须立刻禁用：再点一次会带上新的幂等键，服务层视为一次新作答，
  /// FSRS 会被推进两遍。
  bool _canRate(StudyItemView item) {
    if (_outcome != null || _busy) return false;
    return !_awaitingAnswer(item);
  }

  void _start() {
    if (!mounted) return;
    unawaited(ref.read(studySessionProvider.notifier).start(widget.mode));
  }

  void _setAnswer(String value) => setState(() => _answer = value);

  /// 键盘回车提交。
  ///
  /// 自评缺省为「记得」：用户直接回车说明他不想细究，客观题答错时服务层
  /// 会把「记得」降级为「忘了」。界面不重复这条规则。
  void _submit() => unawaited(_submitWith(ReviewRating.good));

  /// 点某一档自评即提交。
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
