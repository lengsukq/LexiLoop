/// 学习会话页面。
///
/// 旧版 `study-client.tsx` 用 497 行把「取会话、按题型分支、作答、判题、
/// 自评、总结」塞进一个组件（见 `docs/CLEAN_CODE_BASELINE.md`）。这里按
/// 职责拆开：
///
/// - [StudyProgressHeader]：进度与计数，只读；
/// - [StudyPrompt]：题干，按题型分四种形态；
/// - [StudyHintBar]：拼写题的字母提示与提示按钮；
/// - [StudyAnswerArea]：作答控件，每个题型一个组件且自持草稿；
/// - [StudyRatingBar]：四档自评（含间隔预览），**同时是提交入口**；
/// - [StudyFeedbackPanel] / [StudySummaryView]：判定反馈与会话总结；
/// - 本文件只保留「编排」：什么时候开始、什么时候提交、什么时候前进。
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
import 'package:lexiloop/features/study/study_answer.dart';
import 'package:lexiloop/features/study/study_clock.dart';
import 'package:lexiloop/features/study/study_feedback.dart';
import 'package:lexiloop/features/study/study_hint_bar.dart';
import 'package:lexiloop/features/study/study_interval_preview.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/features/study/study_local_verdict.dart';
import 'package:lexiloop/features/study/study_progress_header.dart';
import 'package:lexiloop/features/study/study_prompt.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/study/study_rating.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/features/study/study_states.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/ui/glass.dart';

/// 四档自评快捷键 `1`–`4` 对应的数字键。
///
/// `LogicalKeyboardKey` 不支持算术运算，必须显式列表映射（与 `app.dart`
/// 的导航快捷键同一写法）。
const List<LogicalKeyboardKey> _ratingKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
];

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

class _StudySessionBodyState extends ConsumerState<StudySessionBody>
    with WidgetsBindingObserver {
  ReviewOutcome? _outcome;
  StudyItemView? _answered;
  String? _answer;
  bool _busy = false;

  /// 活跃计时器：只统计「答题中且未揭示答案」的前台时间。
  late final StudyClock _clock;

  /// 当前题目的四档间隔预览；取不到时为空表，按钮显示占位符。
  List<FsrsIntervalPreview> _intervals = const <FsrsIntervalPreview>[];

  /// 已经为哪道题发起过预览请求（失败也不重试，避免答题过程中反复打库）。
  int? _previewItemId;

  /// 正在展示的题目 ID；换题时据此重置计时、提示与预览。
  int? _trackedItemId;

  /// 已经为哪道题预取过真人录音。
  int? _preloadedItemId;

  /// 已揭开的提示层数；每换一题清零。
  int _hintLevel = 0;

  /// 本题是否用过提示；每换一题清零。
  bool _usedHint = false;

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
      _scheduleItemPrep();
    }
  }

  @override
  void dispose() {
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
      _scheduleItemPrep();
      return;
    }
    // 反馈展示期间当前题被冻结（见 _answered），草稿必须留着。
    if (_outcome != null) return;
    if (_itemIdOf(oldWidget.session) != _itemIdOf(widget.session)) {
      _answer = null;
    }
    _scheduleItemPrep();
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
        child: Column(
          children: <Widget>[
            StudyProgressHeader(
              session: session,
              onSkip: _canSkip ? _skip : null,
              onExit: _exit,
            ),
            Expanded(child: _content(item)),
          ],
        ),
      ),
    );
  }

  Widget _content(StudyItemView item) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: <Widget>[
        StudyPrompt(item: item, accent: widget.accent),
        const SizedBox(height: 16),
        ..._hintSection(item),
        _answerSection(item),
        const SizedBox(height: 20),
        _ratingSection(item),
        ..._feedbackSection(item),
      ],
    );
  }

  /// 提示区；只有拼写类题目才有。
  List<Widget> _hintSection(StudyItemView item) {
    if (!studyHintAvailable(item)) return const <Widget>[];
    return <Widget>[
      StudyHintBar(item: item, accent: widget.accent, hint: _hintState(item)),
      const SizedBox(height: 12),
    ];
  }

  /// 作答区。
  Widget _answerSection(StudyItemView item) => StudyAnswerArea(
    item: item,
    outcome: _outcome,
    onAnswer: _setAnswer,
    onSubmit: _submit,
  );

  /// 四档自评（含间隔预览）。
  Widget _ratingSection(StudyItemView item) => StudyRatingBar(
    hint: _ratingHint(item),
    enabled: _canRate(item),
    selected: _outcome?.rating,
    intervals: studyIntervalTexts(_intervals),
    onSelect: _selectRating,
  );

  /// 判定反馈与「下一题」；未提交时为空。
  List<Widget> _feedbackSection(StudyItemView item) {
    final outcome = _outcome;
    if (outcome == null) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 16),
      StudyFeedbackPanel(
        outcome: outcome,
        item: item,
        answer: _answer ?? '',
        usedHint: _usedHint,
      ),
      const SizedBox(height: 16),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: studyButtonHeight),
        child: FilledButton(onPressed: _next, child: const Text('下一题')),
      ),
    ];
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

  /// 跳过按钮是否可用。
  ///
  /// 界面上的按钮与快捷键 `S` 共用它：写成两处迟早会出现
  /// 「按钮灰了但快捷键还能跳过」。
  bool get _canSkip => _outcome == null && !_busy;

  /// 四档自评是否可点。
  ///
  /// **自评按钮就是提交按钮**：旧版的交互是「先作答，再选记得程度」，
  /// 选了即提交。所以这里不是「展示已记录等级」的只读控件。
  ///
  /// 提交后必须立刻禁用：再点一次会带上新的幂等键，服务层视为一次新作答，
  /// FSRS 会被推进两遍。快捷键 `1`–`4` 与空格共用同一个判定。
  bool _canRate(StudyItemView item) {
    if (_outcome != null || _busy) return false;
    return !_awaitingAnswer(item);
  }

  /// 提示区的当前状态。
  StudyHintState _hintState(StudyItemView item) => StudyHintState(
    level: _hintLevel,
    used: _usedHint,
    onHint: _outcome == null && studyHintButtonAvailable(item)
        ? _useHint
        : null,
  );

  void _useHint() {
    setState(() {
      _hintLevel += 1;
      _usedHint = true;
    });
  }

  void _start() {
    if (!mounted) return;
    unawaited(ref.read(studySessionProvider.notifier).start(widget.mode));
  }

  void _setAnswer(String value) {
    setState(() => _answer = value);
    // 客观题「给出作答」的这一刻才是旧版的「揭示答案」：间隔预览在这一刻取。
    final item = _item;
    if (item != null) _ensurePreview(item);
  }

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
    final effective = _effectiveRating(item, rating);
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(studySessionProvider.notifier)
          .submit(
            rating: effective,
            userAnswer: _answer,
            // 活跃计时器给出的时长已经扣掉暂停与空闲；服务层再夹一次上界
            // 兜住崩溃恢复与时钟回拨。
            durationMs: _clock.capture(),
          );
      if (!mounted || outcome == null) return;
      setState(() {
        _outcome = outcome;
        _answered = item;
      });
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(studyErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // 结算时停表；提交失败说明这题还没结束，重新开始累计。
        _clock.setEnabled(enabled: _outcome == null);
      }
    }
  }

  /// 提交前对评级做一次降级。
  ///
  /// 用了提示却仍答得不完全正确时，「记得 / 简单」按「模糊」记录——旧版
  /// `study-client.tsx` 的 `rate()` 里同一条规则。服务层不知道用户点过提示，
  /// 这条判断只能放在界面层；它也是界面层**唯一**改写的评级，其余一律原样提交。
  ReviewRating _effectiveRating(StudyItemView item, ReviewRating rating) {
    if (!_usedHint || !studyHintButtonAvailable(item)) return rating;
    if (studyLocalExact(item: item, answer: _answer ?? '') != false) {
      return rating;
    }
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
    _scheduleItemPrep();
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

  /// 换题（或首帧）之后，为当前题准备预取、间隔预览与计时。
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
      _ensurePreview(item);
    });
  }

  /// 换题时清掉所有「跟着题目走」的状态。
  void _resetItemScopedState() {
    setState(() {
      _hintLevel = 0;
      _usedHint = false;
      _intervals = const <FsrsIntervalPreview>[];
      _previewItemId = null;
    });
    _clock.setEnabled(enabled: _outcome == null);
    _clock.reset();
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

  void _ensurePreview(StudyItemView item) {
    if (_outcome != null || !_canRate(item)) return;
    if (_previewItemId == item.itemId) return;
    _previewItemId = item.itemId;
    unawaited(_loadPreview(item));
  }

  /// 取回四档评级的间隔预览。
  ///
  /// 失败时**不显示间隔**、也不做别的：预览只是「按这一档会排到什么时候」的
  /// 提示，绝不能让它冒泡进作答流程——一次只读查询失败不该让人答不了题。
  Future<void> _loadPreview(StudyItemView item) async {
    List<FsrsIntervalPreview> previews;
    try {
      previews = await ref.read(intervalPreviewLoaderProvider)(item.word.id);
    } on Object {
      previews = const <FsrsIntervalPreview>[];
    }
    if (!mounted || _trackedItemId != item.itemId) return;
    setState(() => _intervals = previews);
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
    final key = event.logicalKey;
    if (_isEditingText) {
      // 正在打字：字母、空格、回车都必须留给输入法；数字键保留（与旧版一致），
      // 否则键盘用户答完拼写题还得先按 Tab 逃出输入框才能选档。
      final rating = _ratingOfKey(key);
      return rating != null && _rateByKey(item, rating);
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(
        speakStudyWord(context, ref, word: item.word, accent: widget.accent),
      );
      return true;
    }
    if (key == LogicalKeyboardKey.keyS) {
      if (!_canSkip) return false;
      unawaited(_skip());
      return true;
    }
    if (_isSubmitKey(key)) {
      if (!_canRate(item)) return false;
      _submit();
      return true;
    }
    final rating = _ratingOfKey(key);
    return rating != null && _rateByKey(item, rating);
  }

  /// 空格与回车：提交（旧版是「揭示答案 / 检查答案」，本版自评即提交）。
  bool _isSubmitKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;

  /// 数字键 `1`–`4` 对应的自评等级；不是这四个键时返回 `null`。
  ReviewRating? _ratingOfKey(LogicalKeyboardKey key) {
    final index = _ratingKeys.indexOf(key);
    return index < 0 ? null : ReviewRating.values[index];
  }

  bool _rateByKey(StudyItemView item, ReviewRating rating) {
    if (!_canRate(item)) return false;
    _selectRating(rating);
    return true;
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
