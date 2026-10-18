/// 学习会话页面。
///
/// 旧版 `study-client.tsx` 用 497 行把「取会话、按题型分支、作答、判题、
/// 自评、总结」塞进一个组件（见 `docs/CLEAN_CODE_BASELINE.md`）。这里按
/// 职责拆开：
///
/// - [StudyProgressHeader]：进度与计数，只读；
/// - [StudyPrompt]：题干与作答指令；
/// - [StudyHintBar]：拼写题的字母提示与提示按钮；
/// - [StudyAnswerArea]：作答控件，每个题型一个组件且自持草稿；
/// - [StudyRevealPanel]：揭示后的判定、正确答案与释义；
/// - [StudyRatingBar]：四档自评（含间隔预览），**同时是提交入口**；
/// - [StudySummaryView]：会话总结；
/// - 本文件只保留「编排」：什么时候揭示、什么时候提交、什么时候前进。
///
/// **流程与 Next 版对齐**：作答 → 揭示（对错/答案/差异）→ 自评（写库）
/// → 自动进入下一题。自评不再发生在看到答案之前，单题界面也不再出现
/// 「回答正确」与「自评：忘了」并排的卡片（见 `docs/FLUTTER_PARITY.md`）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/features/study/study_actions.dart';
import 'package:lexiloop/features/study/study_answer.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_hint_bar.dart';
import 'package:lexiloop/features/study/study_interval_preview.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/features/study/study_progress_header.dart';
import 'package:lexiloop/features/study/study_prompt.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_rating.dart';
import 'package:lexiloop/features/study/study_reveal.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/features/study/study_states.dart';
import 'package:lexiloop/features/study/study_summary.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';

/// 数字键 `1`–`4`。
///
/// `LogicalKeyboardKey` 不支持算术运算，必须显式列表映射（与 `app.dart`
/// 的导航快捷键同一写法）。作答阶段它们选选项，揭示后它们才是自评。
const List<LogicalKeyboardKey> _numberKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

/// 选择题倒计时的刷新间隔（毫秒）。
const int _choiceTickMs = 80;

/// 揭示后把面板滚进视野的时长（毫秒）。
const int _revealScrollMs = 220;

/// 学习会话页面。
///
/// 学习页在 `immersivePaths` 内，外壳不渲染底部导航，因此返回与进度条都由
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

    return session.when(
      loading: () =>
          StudySessionBody(mode: mode, session: null, accent: accent),
      error: (error, _) => PageShell(
        maxWidth: LexiLayout.immersiveMaxWidth,
        child: StudyErrorView(
          message: studyErrorMessage(error),
          // 只失效、不直接 `start`：失效后 `data(null)` 会让主体重建并
          // 在 initState 里启动，直接再调一次 start 会并发开出两个会话。
          onRetry: () => ref.invalidate(studySessionProvider),
          // 沉浸路由上没有导航外壳可以依赖，这一条是唯一的退路。
          onExit: () => leaveStudyToHome(context),
        ),
      ),
      data: (view) =>
          StudySessionBody(mode: mode, session: view, accent: accent),
    );
  }
}

/// 离开学习页：明确回首页，而不是指望返回栈。
///
/// 旧版这里是 `<Link href="/">退出</Link>`（`study-client.tsx:554`），
/// 结算页的「返回今日」同样是 `href="/"`。本函数照旧版做。
///
/// 无路由器时（部分 widget 测试直接 `home: StudyPage(...)`）退回出栈，
/// 保持这些测试的可运行性。
///
/// **抽成顶层函数而不是留在 State 里**：错误态与正常退出必须走同一条路。
/// 两份实现里漏掉「无路由器」兜底的那一份，迟早正好是用户真正会撞上的
/// 那条分支。
void leaveStudyToHome(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    Navigator.maybePop(context);
    return;
  }
  router.go('/');
}

/// 会话主体：持有作答草稿、揭示状态与判定预览，编排各子组件。
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

class _StudySessionBodyState extends ConsumerState<StudySessionBody>
    with WidgetsBindingObserver {
  /// 已经揭示、正在等待自评的题目；为 `null` 表示还在作答阶段。
  ///
  /// **必须冻结**：提交成功后 provider 会立刻指向下一题，而界面还要显示
  /// 当前题的揭示面板，直到 [_advance] 主动清空。
  StudyItemView? _revealItem;

  /// 揭示时的本地判定预览（与服务判题同源）。
  AnswerPreview? _preview;

  /// 当前作答文本。
  String _answer = '';

  /// 揭示时停表得到的作答时长；提交与重试都用它。
  int? _durationMs;

  /// 提交进行中；同时是自评条的禁用条件。
  bool _busy = false;

  /// 已按下、尚未落库的档位（提交瞬间的高亮）。
  ReviewRating? _pendingRating;

  /// 揭示面板的 key，用于把答案滚进视野。
  final GlobalKey _revealKey = GlobalKey();

  /// 活跃计时器：只统计「答题中且未揭示答案」的前台时间。
  late final StudyClock _clock;

  /// 当前题目的四档间隔预览；取不到时为空表，按钮显示占位符。
  List<FsrsIntervalPreview> _intervals = const <FsrsIntervalPreview>[];

  /// 已经为哪道题发起过预览请求（失败也不重试，避免答题过程中反复打库）。
  int? _previewItemId;

  /// 正在展示的题目 ID；换题时据此重置计时、提示与选项门。
  int? _trackedItemId;

  /// 已经为哪道题预取过真人录音。
  int? _preloadedItemId;

  /// 已经为哪道题自动播过音。
  int? _autoSpokenItemId;

  /// 已揭开的提示层数；每换一题清零。
  int _hintLevel = 0;

  /// 本题是否用过提示；每换一题清零。
  bool _usedHint = false;

  /// 选择题选项是否已经显示（受设置里的揭示延迟控制）。
  bool _choicesVisible = true;

  /// 倒计时进度，0–1。
  double _choiceRevealProgress = 1;

  /// 本次延迟的配置秒数。
  int _choiceRevealSeconds = 0;

  Timer? _choiceRevealTimer;
  Timer? _choiceProgressTimer;
  Timer? _autoSpeakTimer;

  @override
  void initState() {
    super.initState();
    _clock = ref.read(studyClockFactoryProvider)();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    // 首帧之后再启动会话：initState 处于构建阶段，此时改 provider 状态会
    // 触发「构建期间修改 provider」的断言。
    if (widget.session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    } else {
      _seedChoiceVisibility(widget.session?.currentItem);
      _scheduleItemPrep();
    }
  }

  @override
  void dispose() {
    _cancelChoiceTimers();
    _autoSpeakTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _clock.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 失焦 / 切后台 / 锁屏一律停止累计：只有真正回到前台才可能继续。
    _clock.setVisible(visible: state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(covariant StudySessionBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session?.id != oldWidget.session?.id) {
      _resetRound();
      _seedChoiceVisibility(widget.session?.currentItem);
      _scheduleItemPrep();
      return;
    }
    // 揭示期间 provider 已经推进到下一题，但画面必须停在当前题的答案上。
    if (_revealItem != null) return;
    final item = widget.session?.currentItem;
    if (item != null && item.itemId != _trackedItemId) {
      _seedChoiceVisibility(item);
    }
    _scheduleItemPrep();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (session == null) {
      return const PageShell(
        maxWidth: LexiLayout.immersiveMaxWidth,
        child: StudyLoadingView(),
      );
    }

    // 没有题目时 `currentItem` 也是 `null`（`resumeIndex >= items.length`），
    // 因此「今天没词可学」与「这一轮做完了」共用结算视图——旧版
    // `study-client.tsx:548` 正是这么做的，只是标题不同。
    final item = _revealItem ?? session.currentItem;
    if (item == null) {
      return PageShell(
        maxWidth: LexiLayout.immersiveMaxWidth,
        scrollable: true,
        child: StudySummaryView(
          session: session,
          onRestart: _restart,
          onHome: _leaveToHome,
        ),
      );
    }

    // 答题区包一层输入监听：指针、滚轮、滚动都算「用户在场」，
    // 空闲判定因此不会被误触发。
    return Listener(
      onPointerDown: (_) => _clock.touch(),
      onPointerSignal: (_) => _clock.touch(),
      onPointerPanZoomStart: (_) => _clock.touch(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _clock.touch();
          return false;
        },
        child: PageShell(
          maxWidth: LexiLayout.immersiveMaxWidth,
          header: StudyProgressHeader(session: session, onExit: _leaveToHome),
          bottomAction: _bottomAction(context, item),
          scrollable: true,
          child: _content(item),
        ),
      ),
    );
  }

  /// 题干、提示、作答控件与揭示面板。
  Widget _content(StudyItemView item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        StudyPrompt(item: item, accent: widget.accent),
        const SizedBox(height: LexiSpace.s16),
        ..._hintSection(item),
        _answerSection(item),
        ..._revealSection(item),
      ],
    );
  }

  /// 提示区；只有未揭示的拼写类题目才有。
  List<Widget> _hintSection(StudyItemView item) {
    if (_revealItem != null || !studyHintAvailable(item)) {
      return const <Widget>[];
    }
    return <Widget>[
      StudyHintBar(item: item, accent: widget.accent, hint: _hintState(item)),
      const SizedBox(height: LexiSpace.s12),
    ];
  }

  /// 作答控件；选择题倒计时期间换成「立即显示选项」。
  Widget _answerSection(StudyItemView item) {
    if (_revealItem == null && !_choicesVisible) {
      return StudyChoiceGate(
        progress: _choiceRevealProgress,
        remainingSeconds: _choiceRemainingSeconds,
        onRevealNow: _revealChoicesNow,
      );
    }
    return StudyAnswerArea(
      item: item,
      answer: _answer,
      revealed: _revealItem != null,
      onAnswer: _onAnswer,
      onCheck: _reveal,
    );
  }

  /// 揭示面板；只在揭示后且预览已算好时出现。
  List<Widget> _revealSection(StudyItemView item) {
    final preview = _preview;
    if (_revealItem == null || preview == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: LexiSpace.s16),
      StudyRevealPanel(
        key: _revealKey,
        item: item,
        preview: preview,
        answer: _answer,
        usedHint: _usedHint,
        accent: widget.accent,
      ),
    ];
  }

  /// 吸底动作条：作答阶段是检查/显示答案，揭示后是四档自评。
  Widget _bottomAction(BuildContext context, StudyItemView item) {
    if (_revealItem != null) {
      return StudyRatingBar(
        hint: _ratingHint(context),
        enabled: !_busy,
        selected: _pendingRating,
        intervals: studyIntervalTexts(_intervals),
        onSelect: _selectRating,
      );
    }
    if (choiceQuestionTypes.contains(item.questionType)) {
      return StudyChoiceActions(
        hint: _choiceHint(context),
        onSkip: () => unawaited(_skip()),
      );
    }
    final showingAnswer = item.questionType == QuestionType.enToZh;
    return StudyCheckActions(
      canCheck: _canReveal(item),
      primaryLabel: showingAnswer ? '显示答案' : '检查答案',
      onSkip: () => unawaited(_skip()),
      onCheck: _reveal,
      onForget: showingAnswer ? null : () => _reveal(allowEmpty: true),
    );
  }

  /// 自评条的提示语。
  String _ratingHint(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= studyWideMinWidth;
    return wide ? '按 1–4 记录熟悉度，选完自动进入下一题' : '选一档熟悉度，选完自动进入下一题';
  }

  /// 选择题动作条的提示语。
  String _choiceHint(BuildContext context) {
    if (!_choicesVisible) return '选项显示后点击作答';
    final wide = MediaQuery.sizeOf(context).width >= studyWideMinWidth;
    return wide ? '点击选项或按 1–4 作答' : '点击选项作答';
  }

  /// 倒计时剩余秒数（向上取整，至少 1）。
  int get _choiceRemainingSeconds {
    if (_choiceRevealSeconds <= 0) return 0;
    final remaining = (_choiceRevealSeconds * (1 - _choiceRevealProgress))
        .ceil();
    return remaining < 1 ? 1 : remaining;
  }

  /// 提示区的当前状态。
  StudyHintState _hintState(StudyItemView item) => StudyHintState(
    level: _hintLevel,
    used: _usedHint,
    onHint: _revealItem == null && studyHintButtonAvailable(item)
        ? _useHint
        : null,
  );

  /// 当前展示的题目。
  StudyItemView? get _item => _revealItem ?? widget.session?.currentItem;

  /// 播放设置；尚未加载时用默认值兜底。
  PlaybackSettings get _playback =>
      ref.read(appSettingsProvider).value?.playback ??
      PlaybackSettings.defaults;

  void _useHint() {
    setState(() {
      _hintLevel += 1;
      _usedHint = true;
    });
  }

  /// 作答内容变化。
  ///
  /// 选择题选中即揭示（只揭示、不写库）；文本题只记录草稿，等「检查答案」。
  void _onAnswer(String value) {
    _clock.touch();
    final item = _item;
    if (item == null) return;
    setState(() => _answer = value);
    if (choiceQuestionTypes.contains(item.questionType)) _reveal();
  }

  /// 是否允许揭示。看词说义没有客观答案，任何时候都可以看答案。
  bool _canReveal(StudyItemView item) {
    if (item.questionType == QuestionType.enToZh) return true;
    return _answer.trim().isNotEmpty;
  }

  /// 揭示答案：冻结当前题、停表、算本地预览、取间隔预览。
  void _reveal({bool allowEmpty = false}) {
    if (_busy) return;
    final item = _item;
    if (item == null || _revealItem != null) return;
    if (!allowEmpty && !_canReveal(item)) return;

    final preview = previewAnswer(
      questionType: item.questionType,
      word: item.word,
      answer: _answer,
    );
    final duration = _clock.capture();
    _cancelChoiceTimers();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _revealItem = item;
      _preview = preview;
      _durationMs = duration;
      _choicesVisible = true;
      _choiceRevealProgress = 1;
    });
    _clock.setEnabled(enabled: false);
    unawaited(_loadPreview(item));
    _scrollRevealIntoView();
  }

  /// 把揭示面板滚进视野：窄屏上它通常在折叠线以下。
  void _scrollRevealIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final revealContext = _revealKey.currentContext;
      if (revealContext == null) return;
      Scrollable.ensureVisible(
        revealContext,
        duration: LexiMotion.of(
          context,
          const Duration(milliseconds: _revealScrollMs),
        ),
      );
    });
  }

  /// 取回四档评级的间隔预览。
  ///
  /// 失败时**不显示间隔**、也不做别的：预览只是「按这一档会排到什么时候」的
  /// 提示，绝不能让它冒泡进作答流程——一次只读查询失败不该让人答不了题。
  Future<void> _loadPreview(StudyItemView item) async {
    if (_previewItemId == item.itemId) return;
    _previewItemId = item.itemId;
    List<FsrsIntervalPreview> previews;
    try {
      previews = await ref.read(intervalPreviewLoaderProvider)(item.word.id);
    } on Object {
      previews = const <FsrsIntervalPreview>[];
    }
    if (!mounted || _revealItem?.itemId != item.itemId) return;
    setState(() => _intervals = previews);
  }

  /// 点某一档自评即提交。
  void _selectRating(ReviewRating rating) {
    if (_revealItem == null || _busy) return;
    unawaited(_submitWith(rating));
  }

  Future<void> _submitWith(ReviewRating rating) async {
    final item = _revealItem;
    if (item == null || _busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final effective = _effectiveRating(item, rating);
    setState(() {
      _busy = true;
      _pendingRating = rating;
    });
    try {
      final outcome = await ref
          .read(studySessionProvider.notifier)
          .submit(
            rating: effective,
            userAnswer: _answer,
            // 揭示时已经停表；重试复用同一段时长，不把等待时间算进去。
            durationMs: _durationMs ?? _clock.capture(),
          );
      if (!mounted) return;
      _notifyOutcome(messenger, outcome);
      _advance();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(studyErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _pendingRating = null;
        });
      }
    }
  }

  /// 提交成功后的两条附加信息；没有就什么都不弹。
  void _notifyOutcome(
    ScaffoldMessengerState messenger,
    ReviewOutcome? outcome,
  ) {
    if (outcome == null) return;
    if (outcome.adaptiveFollowUp != null) {
      messenger.showSnackBar(const SnackBar(content: Text('这个词稍后会再出现一次')));
    } else if (outcome.idempotent) {
      messenger.showSnackBar(const SnackBar(content: Text('重复提交已忽略，排期未重复推进')));
    }
  }

  /// 提交前对评级做一次降级。
  ///
  /// 用了提示却仍答得不完全正确时，「记得 / 简单」按「模糊」记录——旧版
  /// `study-client.tsx` 的 `rate()` 里同一条规则。服务层不知道用户点过提示，
  /// 这条判断只能放在界面层；它也是界面层**唯一**改写的评级，其余一律原样提交。
  ReviewRating _effectiveRating(StudyItemView item, ReviewRating rating) {
    if (!studyHintDowngrades(item, _answer, usedHint: _usedHint)) return rating;
    if (rating == ReviewRating.good || rating == ReviewRating.easy) {
      return ReviewRating.hard;
    }
    return rating;
  }

  Future<void> _skip() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(studySessionProvider.notifier).skip();
      if (!mounted) return;
      _advance();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(studyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 前进到下一题（或总结）：清空所有「跟着这道题走」的状态。
  void _advance() {
    _cancelChoiceTimers();
    _autoSpeakTimer?.cancel();
    setState(() {
      _clearItemState();
      _seedChoiceVisibility(ref.read(studySessionProvider).value?.currentItem);
    });
    _scheduleItemPrep();
  }

  /// 把「跟着当前题走」的字段全部归零。
  ///
  /// [_advance] 与 [_resetRound] 共用：两处各抄一份字段清单，迟早会漏掉
  /// 新增的那个（例如后来的 `_previewItemId`）。
  void _clearItemState() {
    _revealItem = null;
    _preview = null;
    _answer = '';
    _durationMs = null;
    _pendingRating = null;
    _intervals = const <FsrsIntervalPreview>[];
    _previewItemId = null;
    _hintLevel = 0;
    _usedHint = false;
    _choicesVisible = true;
    _choiceRevealProgress = 1;
    _choiceRevealSeconds = 0;
    _trackedItemId = null;
  }

  void _start() {
    if (!mounted) return;
    unawaited(ref.read(studySessionProvider.notifier).start(widget.mode));
  }

  void _restart() {
    _resetRound();
    _start();
  }

  /// 重开一轮：把所有临时状态归零。
  void _resetRound() {
    _cancelChoiceTimers();
    _autoSpeakTimer?.cancel();
    _clearItemState();
    _preloadedItemId = null;
    _autoSpokenItemId = null;
    _clock
      ..setEnabled(enabled: true)
      ..reset();
  }

  /// 换题（或首帧）之后，为当前题准备预取、选项门、自动朗读与计时。
  ///
  /// 放在首帧之后：这些动作都会读写 provider 或 `setState`，在构建期间做
  /// 会直接触发断言。重复调用由 [_trackedItemId] 挡掉。
  void _scheduleItemPrep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item = _item;
      if (item == null || _trackedItemId == item.itemId) return;
      _trackedItemId = item.itemId;
      _resetItemScopedState();
      _preloadAhead(item);
      _startChoiceGate(item);
      _scheduleAutoSpeak(item);
    });
  }

  /// 换题时清掉所有「跟着题目走」的状态。
  void _resetItemScopedState() {
    _autoSpeakTimer?.cancel();
    setState(() {
      _hintLevel = 0;
      _usedHint = false;
      _answer = '';
      _intervals = const <FsrsIntervalPreview>[];
      _previewItemId = null;
      _choicesVisible = true;
      _choiceRevealProgress = 1;
      _choiceRevealSeconds = 0;
    });
    _clock.setEnabled(enabled: _revealItem == null);
    _clock.reset();
  }

  /// 在 prep 之前的首帧就决定选项是否显示。
  ///
  /// 不预置的话，延迟 > 0 时选项会先渲染一帧、再被 prep 隐藏——肉眼能看到的
  /// 闪烁。这里只写字段、不调 `setState`：调用点都在 `build` 之前
  /// （`initState` / `didUpdateWidget` / `setState` 内部），下一次构建自然会
  /// 读到新值。
  void _seedChoiceVisibility(StudyItemView? item) {
    if (item == null) return;
    final seconds = _playback.choiceRevealDelaySeconds;
    final gated =
        choiceQuestionTypes.contains(item.questionType) &&
        item.choices.isNotEmpty &&
        seconds > 0;
    _choicesVisible = !gated;
    _choiceRevealProgress = gated ? 0 : 1;
    _choiceRevealSeconds = gated ? seconds : 0;
  }

  /// 按设置决定是否延迟显示选项；延迟 0 时直接显示。
  void _startChoiceGate(StudyItemView item) {
    _cancelChoiceTimers();
    final gated =
        choiceQuestionTypes.contains(item.questionType) &&
        item.choices.isNotEmpty;
    final seconds = _playback.choiceRevealDelaySeconds;
    if (!gated || seconds <= 0) {
      setState(() {
        _choicesVisible = true;
        _choiceRevealProgress = 1;
        _choiceRevealSeconds = 0;
      });
      return;
    }

    final totalTicks = (seconds * 1000 / _choiceTickMs).ceil();
    var ticks = 0;
    setState(() {
      _choicesVisible = false;
      _choiceRevealProgress = 0;
      _choiceRevealSeconds = seconds;
    });
    _choiceRevealTimer = Timer(Duration(seconds: seconds), _revealChoicesNow);
    _choiceProgressTimer = Timer.periodic(
      const Duration(milliseconds: _choiceTickMs),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        ticks += 1;
        setState(() {
          _choiceRevealProgress = (ticks / totalTicks).clamp(0, 1);
        });
        if (ticks >= totalTicks) timer.cancel();
      },
    );
  }

  /// 立即显示选项；Space / 「立即显示选项」共用。
  void _revealChoicesNow() {
    _cancelChoiceTimers();
    if (!mounted || _revealItem != null) return;
    setState(() {
      _choicesVisible = true;
      _choiceRevealProgress = 1;
    });
  }

  void _cancelChoiceTimers() {
    _choiceRevealTimer?.cancel();
    _choiceRevealTimer = null;
    _choiceProgressTimer?.cancel();
    _choiceProgressTimer = null;
  }

  /// 进入题目后静默播一次发音（受设置与题型限制）。
  void _scheduleAutoSpeak(StudyItemView item) {
    if (_autoSpokenItemId == item.itemId) return;
    final playback = _playback;
    if (!playback.autoPlayPronunciation ||
        !studyAutoSpeakAllowed(item.questionType)) {
      return;
    }
    _autoSpokenItemId = item.itemId;
    _autoSpeakTimer?.cancel();
    _autoSpeakTimer = Timer(
      const Duration(milliseconds: studyAutoSpeakDelayMs),
      () {
        if (!mounted) return;
        studyAutoSpeak(
          speaker: ref.read(wordSpeakerProvider),
          playback: playback,
          accent: widget.accent,
          item: item,
        );
      },
    );
  }

  /// 预取当前题及其后共 [studyPreloadAheadCount] 道题的真人录音。
  void _preloadAhead(StudyItemView item) {
    final session = widget.session;
    if (session == null || _preloadedItemId == item.itemId) return;
    _preloadedItemId = item.itemId;
    final index = session.items.indexWhere(
      (candidate) => candidate.itemId == item.itemId,
    );
    if (index < 0) return;
    final playback =
        ref.read(appSettingsProvider).value?.playback ??
        PlaybackSettings.defaults;
    studyPreloadAhead(
      speaker: ref.read(wordSpeakerProvider),
      items: session.items.skip(index).take(studyPreloadAheadCount),
      accent: widget.accent,
      playback: playback,
    );
  }

  /// 键盘事件入口。
  ///
  /// 挂在 `HardwareKeyboard` 上而不是 `Focus` 上：后者会抢走文本输入框的焦点，
  /// 而拼写题必须能打字。代价是这里**先于**焦点派发运行，所以要自己让位给
  /// 输入法（见 [_isEditingText]）。
  bool _handleKeyEvent(KeyEvent event) {
    _clock.touch();
    if (event is! KeyDownEvent) return false;
    // 带 ⌘/Ctrl 的组合留给全局导航快捷键（`app.dart` 的 ⌘1–8）。
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    final item = _item;
    if (item == null || _busy) return false;
    // 正在打字：字母、空格、数字全部让给输入法；回车由输入框的
    // `onSubmitted` 转成「检查答案」。
    if (_isEditingText) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(
        speakStudyWord(context, ref, word: item.word, accent: widget.accent),
      );
      return true;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_skip());
      return true;
    }
    return _revealItem == null
        ? _handleAnsweringKey(item, key)
        : _handleRevealedKey(key);
  }

  /// 作答阶段的键盘语义。
  ///
  /// **数字键在这一阶段只用于选选项**：旧版把 `1–4` 一律当自评，用户想按
  /// `1` 选第一个选项时反而给自己记了一次「忘了」——截图里那条矛盾的
  /// 「回答正确 / 自评：忘了」很可能就是这么来的。
  bool _handleAnsweringKey(StudyItemView item, LogicalKeyboardKey key) {
    if (choiceQuestionTypes.contains(item.questionType)) {
      if (!_choicesVisible) {
        if (!_isSubmitKey(key)) return false;
        _revealChoicesNow();
        return true;
      }
      final index = _digitIndex(key);
      if (index == null || index >= item.choices.length) return false;
      _onAnswer(item.choices[index]);
      return true;
    }
    if (!_isSubmitKey(key) || !_canReveal(item)) return false;
    _reveal();
    return true;
  }

  /// 揭示后的键盘语义：`1–4` 自评，`Space/Enter` 按「记得」。
  bool _handleRevealedKey(LogicalKeyboardKey key) {
    final rating = _ratingOfKey(key);
    if (rating != null) {
      _selectRating(rating);
      return true;
    }
    if (!_isSubmitKey(key)) return false;
    _selectRating(ReviewRating.good);
    return true;
  }

  /// 空格与回车：作答阶段是检查/显示答案，揭示后是「记得」。
  bool _isSubmitKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  /// 数字键 `1`–`4` 的序号（0–3）；不是这四个键时返回 `null`。
  int? _digitIndex(LogicalKeyboardKey key) {
    final index = _numberKeys.indexOf(key);
    return index < 0 ? null : index;
  }

  /// 数字键对应的自评等级；不是这四个键时返回 `null`。
  ReviewRating? _ratingOfKey(LogicalKeyboardKey key) {
    final index = _digitIndex(key);
    return index == null ? null : ReviewRating.values[index];
  }

  /// 焦点是否在可编辑文本里。
  ///
  /// 用 [EditableText] 判断而不是「有没有焦点节点」：文本输入框内部也挂了
  /// `Focus`，只看焦点存在与否会把「点过输入框但已经失焦」也当成在打字。
  bool get _isEditingText {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// 离开学习页，回到今日。
  ///
  /// **不能只 `Navigator.maybePop`**：学习页是 `StatefulShellRoute` 的
  /// **分支根路由**，栈里没有上一页，`maybePop` 什么都不会发生；而沉浸模式
  /// 又不渲染外壳导航（`destinations.dart` 的 `immersivePaths`），于是用户
  /// 会被困在这一页——没有题目可做时尤其明显，整页只剩一个点了没反应的按钮。
  ///
  /// 旧版这里是 `<Link href="/">退出</Link>`（`study-client.tsx:554`），
  /// 结算页的「返回今日」同样是 `href="/"`。本方法照旧版做：**明确回首页**，
  /// 而不是指望返回栈。
  ///
  /// 无路由器时（部分 widget 测试直接 `home: StudyPage(...)`）退回出栈，
  /// 保持这些测试的可运行性。
  void _leaveToHome() => leaveStudyToHome(context);
}
