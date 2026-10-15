/// 文章导入向导的状态与数据提供者。
///
/// 对应旧版 `src/components/add/article-tab.tsx` 的 20 个 `useState`。
/// 旧版把「输入 / 分析中 / 预览 / 提交中 / 完成」五个步骤与分段进度、
/// 勾选集合散在组件里，任何一个分支漏改一个 `setState` 都会留下脏状态；
/// 这里收进一个不可变状态对象，步骤切换只能整份替换。
///
/// **状态为什么分四块**：架构守卫要求函数 ≤40 行，而一个 17 字段的
/// `copyWith` 必然超限。按「输入 / 分析 / 勾选 / 结果」拆开后，每块的
/// `copyWith` 都在十几行内，且读者一眼能看出「哪一步改了哪一块」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/article_import/article_candidates.dart';
import 'package:lexiloop/domain/article_import/article_extract.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/add/add_providers.dart';
import 'package:lexiloop/services/article_import/article_ai_selector.dart';
import 'package:lexiloop/services/article_import/article_import_service.dart';

/// 向导步骤。
enum ArticleStep {
  /// 粘贴与参数选择。
  input,

  /// 正在分析（含分段分析）。
  analyzing,

  /// 预览与勾选。
  preview,

  /// 正在写入词库。
  committing,

  /// 导入完成。
  success,
}

/// 候选类型筛选。
enum ArticleCandidateFilter {
  /// 全部。
  all,

  /// 单词。
  word,

  /// 短语。
  phrase,

  /// 句子。
  sentence,
}

/// 单个分段的进度状态。
enum ArticleSegmentStatus {
  /// 等待中。
  idle,

  /// 请求中。
  loading,

  /// 已成功。
  success,

  /// 失败（可重试）。
  error,
}

/// AI 选词器（按当前设置解析 LLM 配置）。
final Provider<ArticleAiSelector> articleAiSelectorProvider =
    Provider<ArticleAiSelector>(
      (ref) => SettingsArticleAiSelector(
        ref.watch(settingsServiceProvider),
        ref.watch(httpFetcherProvider),
      ),
    );

/// 文章导入服务。
///
/// 词条写入复用 [wordEditServiceProvider]（与手动添加同一条路径），
/// 不另建一套 INSERT。
final Provider<ArticleImportService> articleImportServiceProvider =
    Provider<ArticleImportService>(
      (ref) => ArticleImportService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
        ref.watch(wordEditServiceProvider),
        ref.watch(articleAiSelectorProvider),
      ),
    );

/// 一个分段的界面状态。
class ArticleSegmentState {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.index,
    required this.text,
    required this.charCount,
    required this.previewText,
    this.status = ArticleSegmentStatus.idle,
    this.preview,
    this.error,
  });

  /// 分段 ID。
  final String id;

  /// 分段序号。
  final int index;

  /// 分段正文。
  final String text;

  /// 字符数。
  final int charCount;

  /// 列表里展示的片段。
  final String previewText;

  /// 状态。
  final ArticleSegmentStatus status;

  /// 成功时的预览（同批的多个段共享同一个对象）。
  final ArticleImportPreview? preview;

  /// 失败原因。
  final String? error;

  /// 复制并改写状态。
  ArticleSegmentState copyWith({
    ArticleSegmentStatus? status,
    ArticleImportPreview? preview,
    String? error,
    bool clearPreview = false,
    bool clearError = false,
  }) => ArticleSegmentState(
    id: id,
    index: index,
    text: text,
    charCount: charCount,
    previewText: previewText,
    status: status ?? this.status,
    preview: clearPreview ? null : (preview ?? this.preview),
    error: clearError ? null : (error ?? this.error),
  );
}

/// 分段进度。
class ArticleBatchProgress {
  /// 以各字段构造。
  const new({required this.done, required this.total, required this.failed});

  /// 已完成批次数。
  final int done;

  /// 总批次数。
  final int total;

  /// 失败批次数。
  final int failed;
}

/// 输入块状态。
class ArticleDraftState {
  /// 以各字段构造。
  const new({
    this.text = '',
    this.examTargets = const <VocabularyLevel>[],
    this.examTargetsLoaded = false,
    this.segmentsPerBatch = 1,
    this.plan,
  });

  /// 粘贴的正文。
  final String text;

  /// 勾选的考试目标。
  final List<VocabularyLevel> examTargets;

  /// 是否已从设置读过考试目标。
  final bool examTargetsLoaded;

  /// 每批段数。
  final int segmentsPerBatch;

  /// 分段方案（正文或每批段数变化时重算）。
  ///
  /// **必须缓存**：分段要跑正则与多次 `sublist`，五万字的文章逐键重算会卡住
  /// 输入框；旧版用 `useMemo` 解决同一问题。
  final ArticleSegmentPlan? plan;

  /// 复制并改写。
  ArticleDraftState copyWith({
    String? text,
    List<VocabularyLevel>? examTargets,
    bool? examTargetsLoaded,
    int? segmentsPerBatch,
    ArticleSegmentPlan? plan,
    bool clearPlan = false,
  }) => ArticleDraftState(
    text: text ?? this.text,
    examTargets: examTargets ?? this.examTargets,
    examTargetsLoaded: examTargetsLoaded ?? this.examTargetsLoaded,
    segmentsPerBatch: segmentsPerBatch ?? this.segmentsPerBatch,
    plan: clearPlan ? null : (plan ?? this.plan),
  );
}

/// 分析块状态。
class ArticleAnalysisState {
  /// 以各字段构造。
  const new({
    this.step = ArticleStep.input,
    this.preview,
    this.finalToken,
    this.segments = const <ArticleSegmentState>[],
    this.useSegmented = false,
    this.progress,
  });

  /// 当前步骤。
  final ArticleStep step;

  /// 当前展示的预览（分段分析时是各批合并出来的结果）。
  final ArticleImportPreview? preview;

  /// 可提交的预览令牌（分段流程要等服务端合并后才拿得到）。
  final String? finalToken;

  /// 分段状态列表。
  final List<ArticleSegmentState> segments;

  /// 是否走了分段流程。
  final bool useSegmented;

  /// 分段进度。
  final ArticleBatchProgress? progress;

  /// 复制并改写。
  ArticleAnalysisState copyWith({
    ArticleStep? step,
    ArticleImportPreview? preview,
    String? finalToken,
    List<ArticleSegmentState>? segments,
    bool? useSegmented,
    ArticleBatchProgress? progress,
    bool clearPreview = false,
    bool clearFinalToken = false,
    bool clearProgress = false,
  }) => ArticleAnalysisState(
    step: step ?? this.step,
    preview: clearPreview ? null : (preview ?? this.preview),
    finalToken: clearFinalToken ? null : (finalToken ?? this.finalToken),
    segments: segments ?? this.segments,
    useSegmented: useSegmented ?? this.useSegmented,
    progress: clearProgress ? null : (progress ?? this.progress),
  );
}

/// 勾选块状态。
class ArticleSelectionState {
  /// 以各字段构造。
  const new({
    this.selected = const <String>{},
    this.mode = ImportMode.fillMissing,
    this.filter = ArticleCandidateFilter.all,
    this.showRecommendedOnly = false,
    this.resetLearningProgress = false,
  });

  /// 已勾选的候选键（小写）。
  final Set<String> selected;

  /// 导入模式。
  final ImportMode mode;

  /// 类型筛选。
  final ArticleCandidateFilter filter;

  /// 是否只看 AI 推荐。
  final bool showRecommendedOnly;

  /// 是否重置本次命中已有词条的学习进度。
  ///
  /// 对应旧版 `components/add/article-tab.tsx:475,526`。缺省关闭：它是本页
  /// 唯一一个会删除既有学习数据的开关，不该默认打开。
  final bool resetLearningProgress;

  /// 复制并改写。
  ArticleSelectionState copyWith({
    Set<String>? selected,
    ImportMode? mode,
    ArticleCandidateFilter? filter,
    bool? showRecommendedOnly,
    bool? resetLearningProgress,
  }) => ArticleSelectionState(
    selected: selected ?? this.selected,
    mode: mode ?? this.mode,
    filter: filter ?? this.filter,
    showRecommendedOnly: showRecommendedOnly ?? this.showRecommendedOnly,
    resetLearningProgress: resetLearningProgress ?? this.resetLearningProgress,
  );
}

/// 向导的完整状态。
class ArticleWizardState {
  /// 以各字段构造。
  const new({
    this.draft = const ArticleDraftState(),
    this.analysis = const ArticleAnalysisState(),
    this.selection = const ArticleSelectionState(),
    this.error,
    this.result,
  });

  /// 输入块。
  final ArticleDraftState draft;

  /// 分析块。
  final ArticleAnalysisState analysis;

  /// 勾选块。
  final ArticleSelectionState selection;

  /// 面向用户的错误提示。
  final String? error;

  /// 提交结果。
  final ArticleCommitResult? result;

  /// 复制并改写。
  ArticleWizardState copyWith({
    ArticleDraftState? draft,
    ArticleAnalysisState? analysis,
    ArticleSelectionState? selection,
    String? error,
    bool clearError = false,
    ArticleCommitResult? result,
    bool clearResult = false,
  }) => ArticleWizardState(
    draft: draft ?? this.draft,
    analysis: analysis ?? this.analysis,
    selection: selection ?? this.selection,
    error: clearError ? null : (error ?? this.error),
    result: clearResult ? null : (result ?? this.result),
  );

  /// 正文字符数。
  int get charCount => draft.text.length;

  /// 是否可以发起分析。
  bool get canAnalyze =>
      charCount >= minArticleChars && charCount <= maxArticleChars;

  /// 当前预览。
  ArticleImportPreview? get preview => analysis.preview;

  /// 推荐候选键（小写）。
  Set<String> get recommendedKeys => <String>{
    for (final key in preview?.recommendedKeys ?? const <String>[])
      key.toLowerCase(),
  };

  /// 当前筛选下可见的候选。
  List<ArticleCandidate> get visibleCandidates {
    final current = preview;
    if (current == null) return const <ArticleCandidate>[];
    return <ArticleCandidate>[
      for (final candidate in current.candidates)
        if (_matchesFilter(candidate) &&
            (!selection.showRecommendedOnly ||
                candidate.isKnown ||
                recommendedKeys.contains(articleSelectionKey(candidate)) ||
                recommendedKeys.contains(
                  candidate.normalizedTerm.toLowerCase(),
                )))
          candidate,
    ];
  }

  /// 按类型分组的候选（分组不看筛选）。
  List<ArticleCandidate> grouped(ArticleCandidateFilter filter) {
    final current = preview;
    if (current == null) return const <ArticleCandidate>[];
    return <ArticleCandidate>[
      for (final candidate in current.candidates)
        if (_filterOf(candidate) == filter) candidate,
    ];
  }

  /// 待学候选总数。
  int get candidateCount => preview?.candidateCount ?? 0;

  /// 已成功的分段数。
  int get successSegmentCount => analysis.segments
      .where((segment) => segment.status == ArticleSegmentStatus.success)
      .length;

  /// AI 回退的批次序号（请求成功但 `aiError` 非空）。
  List<int> get aiFallbackBatches => <int>[
    for (final batch in draft.plan?.batches ?? const <ArticleBatch>[])
      if (_batchHasAiFallback(batch)) batch.batchIndex,
  ];

  /// 失败的批次序号。
  List<int> get failedBatches => <int>[
    for (final batch in draft.plan?.batches ?? const <ArticleBatch>[])
      if (_batchHasError(batch)) batch.batchIndex,
  ];

  bool _matchesFilter(ArticleCandidate candidate) =>
      selection.filter == ArticleCandidateFilter.all ||
      _filterOf(candidate) == selection.filter;

  bool _batchHasAiFallback(ArticleBatch batch) => analysis.segments.any(
    (segment) =>
        batch.segmentIds.contains(segment.id) &&
        segment.status == ArticleSegmentStatus.success &&
        segment.preview?.aiError != null,
  );

  bool _batchHasError(ArticleBatch batch) => analysis.segments.any(
    (segment) =>
        batch.segmentIds.contains(segment.id) &&
        segment.status == ArticleSegmentStatus.error,
  );
}

/// 文章导入向导的状态管理器。
class ArticleWizardNotifier extends Notifier<ArticleWizardState> {
  @override
  ArticleWizardState build() => const ArticleWizardState();

  ArticleImportService get _service => ref.read(articleImportServiceProvider);

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 送入服务的考试目标：一个都没勾时传 `null`，由服务回退到设置。
  ///
  /// 与旧版 `examTargets: examTargets.length ? examTargets : undefined` 一致。
  List<VocabularyLevel>? get _examTargets =>
      state.draft.examTargets.isEmpty ? null : state.draft.examTargets;

  /// 覆盖正文，并按需重算分段方案。
  void setArticleText(String text) {
    state = state.copyWith(
      draft: state.draft.copyWith(
        text: text,
        plan: _planFor(text, state.draft.segmentsPerBatch),
      ),
      clearError: true,
    );
  }

  /// 调整每批段数并重算分段方案。
  void setSegmentsPerBatch(int value) {
    final clamped = value.clamp(1, maxArticleSegmentsPerBatch);
    state = state.copyWith(
      draft: state.draft.copyWith(
        segmentsPerBatch: clamped,
        plan: _planFor(state.draft.text, clamped),
      ),
    );
  }

  /// 从设置读入考试目标（进入页面时调用一次）。
  Future<void> loadExamTargets() async {
    final settings = await ref.read(settingsServiceProvider).load();
    state = state.copyWith(
      draft: state.draft.copyWith(
        examTargets: settings.examTargets,
        examTargetsLoaded: true,
      ),
    );
  }

  /// 勾选 / 取消一个考试目标。
  void toggleExamTarget(VocabularyLevel target) {
    final current = state.draft.examTargets;
    final next = current.contains(target)
        ? <VocabularyLevel>[
            for (final item in current)
              if (item != target) item,
          ]
        : <VocabularyLevel>[...current, target];
    state = state.copyWith(draft: state.draft.copyWith(examTargets: next));
  }

  /// 清空考试目标（回到自适应）。
  void clearExamTargets() => state = state.copyWith(
    draft: state.draft.copyWith(examTargets: const <VocabularyLevel>[]),
  );

  /// 切换导入模式。
  void setMode(ImportMode mode) =>
      state = state.copyWith(selection: state.selection.copyWith(mode: mode));

  /// 切换「重置已有词条的学习进度」。
  void setResetLearningProgress({required bool value}) =>
      state = state.copyWith(
        selection: state.selection.copyWith(resetLearningProgress: value),
      );

  /// 切换类型筛选。
  void setFilter(ArticleCandidateFilter filter) => state = state.copyWith(
    selection: state.selection.copyWith(filter: filter),
  );

  /// 切换「仅看 AI 推荐」。
  void setShowRecommendedOnly({required bool value}) => state = state.copyWith(
    selection: state.selection.copyWith(showRecommendedOnly: value),
  );

  /// 勾选 / 取消一个候选。
  void toggleKey(String key) {
    final lower = key.toLowerCase();
    final next = <String>{...state.selection.selected};
    if (!next.remove(lower)) next.add(lower);
    state = state.copyWith(selection: state.selection.copyWith(selected: next));
  }

  /// 只选推荐项。
  void selectRecommended() {
    final preview = state.preview;
    if (preview == null) return;
    final keys = state.recommendedKeys;
    state = state.copyWith(
      selection: state.selection.copyWith(
        selected: keys.isNotEmpty
            ? keys
            : <String>{
                for (final term in preview.recommendedTerms)
                  articleCandidateKey(LexicalContentType.word, term),
              },
      ),
    );
  }

  /// 全选当前筛选下可见的待学候选。
  void selectAllVisible() {
    state = state.copyWith(
      selection: state.selection.copyWith(
        selected: <String>{
          ...state.selection.selected,
          for (final candidate in state.visibleCandidates)
            if (candidate.isCandidate)
              articleSelectionKey(candidate).toLowerCase(),
        },
      ),
    );
  }

  /// 清空勾选。
  void clearSelection() => state = state.copyWith(
    selection: state.selection.copyWith(selected: const <String>{}),
  );

  /// 单次分析整篇文章。
  Future<void> analyzeSingle() async {
    if (!_guardAnalyzable()) return;
    _resetForAnalysis(segmented: false);
    try {
      final preview = await _service.preview(
        articleText: state.draft.text,
        examTargets: _examTargets,
        now: _now(),
      );
      _applySinglePreview(preview);
    } on AppError catch (error) {
      _failToInput(error);
    }
  }

  /// 分段分析：每完成一批就并进预览。
  Future<void> analyzeSegmented() async {
    final plan = state.draft.plan;
    if (plan == null || !_guardAnalyzable()) return;
    _resetForAnalysis(segmented: true, plan: plan);
    final results = <int, ArticleImportPreview>{};
    final failures = <int, String>{};
    await for (final outcome in _service.previewSegments(
      articleText: state.draft.text,
      segmentsPerBatch: state.draft.segmentsPerBatch,
      examTargets: _examTargets,
      now: _now(),
    )) {
      _recordOutcome(outcome, plan, results, failures);
    }
    if (results.isEmpty) {
      _failSegmented(failures);
      return;
    }
    await _finalizeSegmented(results);
  }

  /// 重试单个批次。
  Future<void> retryBatch(int batchIndex) async {
    final plan = state.draft.plan;
    if (plan == null) return;
    final batch = plan.batches.firstWhere(
      (item) => item.batchIndex == batchIndex,
      orElse: () => plan.batches.first,
    );
    state = state.copyWith(
      analysis: state.analysis.copyWith(
        segments: _markBatch(
          batch,
          status: ArticleSegmentStatus.loading,
          clearPreview: true,
        ),
      ),
      clearError: true,
    );
    try {
      final preview = await _service.preview(
        articleText: _batchText(plan, batch),
        examTargets: _examTargets,
        now: _now(),
      );
      state = state.copyWith(
        analysis: state.analysis.copyWith(
          segments: _markBatch(
            batch,
            status: ArticleSegmentStatus.success,
            preview: preview,
          ),
        ),
      );
      await _refreshMerge();
    } on AppError catch (error) {
      _failBatch(batch, error);
    }
  }

  /// 依次重试全部失败批次。
  Future<void> retryFailedBatches() async {
    for (final index in state.failedBatches) {
      await retryBatch(index);
    }
  }

  /// 依次重试全部「AI 回退」批次。
  Future<void> retryAiFallbackBatches() async {
    for (final index in state.aiFallbackBatches) {
      await retryBatch(index);
    }
  }

  /// 提交勾选的词条。
  Future<void> commit() async {
    final token = state.analysis.finalToken;
    if (token == null) return;
    if (state.selection.selected.isEmpty) {
      state = state.copyWith(error: '请至少选择一个词条再导入。');
      return;
    }
    state = state.copyWith(
      analysis: state.analysis.copyWith(step: ArticleStep.committing),
      clearError: true,
    );
    try {
      final result = await _service.commit(
        previewToken: token,
        selectedKeys: state.selection.selected,
        mode: state.selection.mode,
        now: _now(),
        resetLearningProgress: state.selection.resetLearningProgress,
      );
      state = state.copyWith(
        analysis: state.analysis.copyWith(
          step: ArticleStep.success,
          clearFinalToken: true,
        ),
        result: result,
      );
    } on AppError catch (error) {
      state = state.copyWith(
        analysis: state.analysis.copyWith(step: ArticleStep.preview),
        error: articleImportErrorMessage(error),
      );
    }
  }

  /// 回到「粘贴」步骤，保留语言与考试目标。
  void restart() {
    state = ArticleWizardState(
      draft: state.draft.copyWith(text: '', clearPlan: true),
    );
  }

  // ── 内部工具 ──

  /// 校验是否可分析；不可分析时写入提示并返回 `false`。
  bool _guardAnalyzable() {
    if (state.canAnalyze) return true;
    state = state.copyWith(
      error: '文章至少需要 $minArticleChars 个字符，且不能超过 $maxArticleChars 字符。',
    );
    return false;
  }

  /// 进入「分析中」：清掉上一次的预览、勾选与结果。
  void _resetForAnalysis({required bool segmented, ArticleSegmentPlan? plan}) {
    final progress = segmented && plan != null
        ? ArticleBatchProgress(done: 0, total: plan.batches.length, failed: 0)
        : null;
    state = state.copyWith(
      analysis: state.analysis.copyWith(
        step: ArticleStep.analyzing,
        clearPreview: true,
        clearFinalToken: true,
        segments: segmented && plan != null
            ? _idleSegments(plan)
            : const <ArticleSegmentState>[],
        useSegmented: segmented,
        progress: progress,
        clearProgress: progress == null,
      ),
      selection: state.selection.copyWith(
        selected: const <String>{},
        filter: ArticleCandidateFilter.all,
        showRecommendedOnly: false,
      ),
      clearError: true,
      clearResult: true,
    );
  }

  /// 单次分析成功后进入预览：勾选默认取推荐项。
  void _applySinglePreview(ArticleImportPreview preview) {
    state = state.copyWith(
      analysis: state.analysis.copyWith(
        step: ArticleStep.preview,
        preview: preview,
        finalToken: preview.previewToken,
      ),
      selection: state.selection.copyWith(
        selected: initialSelectionKeys(preview),
        showRecommendedOnly: _showRecommendedOnly(preview),
      ),
    );
  }

  /// 回到粘贴步骤并给出原因。
  void _failToInput(AppError error) {
    state = state.copyWith(
      analysis: state.analysis.copyWith(step: ArticleStep.input),
      error: articleImportErrorMessage(error),
    );
  }

  /// 记录一批结果（成功与失败分开收集），并即时合并展示。
  void _recordOutcome(
    ArticleSegmentOutcome outcome,
    ArticleSegmentPlan plan,
    Map<int, ArticleImportPreview> results,
    Map<int, String> failures,
  ) {
    if (outcome.isSuccess) {
      results[outcome.batchIndex] = outcome.preview!;
    } else {
      failures[outcome.batchIndex] = outcome.error!;
    }
    _applyOutcome(outcome, plan, results, failures);
  }

  /// 所有批次都失败：回到粘贴步骤并给出第一条原因。
  void _failSegmented(Map<int, String> failures) {
    state = state.copyWith(
      analysis: state.analysis.copyWith(step: ArticleStep.input),
      error: failures.values.isEmpty ? '所有段落均分析失败，请重试。' : failures.values.first,
    );
  }

  /// 单批重试失败：把原因挂在这一批上，同时作为页面级提示。
  void _failBatch(ArticleBatch batch, AppError error) {
    final message = articleImportErrorMessage(error);
    state = state.copyWith(
      analysis: state.analysis.copyWith(
        segments: _markBatch(
          batch,
          status: ArticleSegmentStatus.error,
          error: message,
        ),
      ),
      error: message,
    );
  }

  ArticleSegmentPlan? _planFor(String text, int segmentsPerBatch) {
    if (text.trim().length < minArticleChars) return null;
    final plan = buildArticleSegmentPlan(
      text,
      segmentsPerBatch: segmentsPerBatch,
    );
    return plan.segments.isEmpty ? null : plan;
  }

  List<ArticleSegmentState> _idleSegments(ArticleSegmentPlan plan) =>
      <ArticleSegmentState>[
        for (final segment in plan.segments)
          ArticleSegmentState(
            id: segment.id,
            index: segment.index,
            text: segment.text,
            charCount: segment.charCount,
            previewText: segment.text.length > articleSegmentPreviewChars
                ? segment.text.substring(0, articleSegmentPreviewChars)
                : segment.text,
          ),
      ];

  String _batchText(ArticleSegmentPlan plan, ArticleBatch batch) {
    final texts = <String, String>{
      for (final segment in plan.segments) segment.id: segment.text,
    };
    return <String>[for (final id in batch.segmentIds) texts[id] ?? '']
        .join('\n\n');
  }

  /// 把一个批次结果并进状态（含即时合并展示）。
  void _applyOutcome(
    ArticleSegmentOutcome outcome,
    ArticleSegmentPlan plan,
    Map<int, ArticleImportPreview> results,
    Map<int, String> failures,
  ) {
    final batch = plan.batches[outcome.batchIndex];
    final segments = outcome.isSuccess
        ? _markBatch(
            batch,
            status: ArticleSegmentStatus.success,
            preview: outcome.preview,
          )
        : _markBatch(
            batch,
            status: ArticleSegmentStatus.error,
            error: outcome.error,
          );
    final merged = mergeArticlePreviews(results.values.toList());
    state = state.copyWith(
      analysis: state.analysis.copyWith(
        segments: segments,
        progress: ArticleBatchProgress(
          done: results.length,
          total: plan.batches.length,
          failed: failures.length,
        ),
        preview: merged,
      ),
      selection: merged == null
          ? state.selection
          : state.selection.copyWith(selected: _unionSelection(merged)),
    );
  }

  /// 分段全跑完后向服务要一个可提交的合并预览。
  Future<void> _finalizeSegmented(
    Map<int, ArticleImportPreview> results,
  ) async {
    try {
      final merged = await _service.mergePreviews(
        tokens: <String>[
          for (final preview in results.values) preview.previewToken,
        ],
        now: _now(),
      );
      state = state.copyWith(
        analysis: state.analysis.copyWith(
          step: ArticleStep.preview,
          preview: merged,
          finalToken: merged.previewToken,
        ),
        selection: state.selection.copyWith(selected: _unionSelection(merged)),
      );
    } on AppError catch (error) {
      // 服务端合并不出来时**不**退回「拿某一批的令牌去提交」：
      // 那会静默导入残缺的一部分，比明确报错糟得多。
      state = state.copyWith(
        analysis: state.analysis.copyWith(step: ArticleStep.preview),
        error: articleImportErrorMessage(error),
      );
    }
  }

  /// 重试成功后重新合并所有已成功批次。
  Future<void> _refreshMerge() async {
    final previews = _successPreviews();
    if (previews.isEmpty) return;
    final merged = mergeArticlePreviews(previews);
    if (merged == null) return;
    state = state.copyWith(
      analysis: state.analysis.copyWith(preview: merged),
      selection: state.selection.copyWith(selected: _unionSelection(merged)),
    );
    await _finalizeSegmented(<int, ArticleImportPreview>{
      for (var index = 0; index < previews.length; index += 1)
        index: previews[index],
    });
  }

  /// 已成功分段的预览（按令牌去重：同批的多个段共享同一个对象）。
  List<ArticleImportPreview> _successPreviews() {
    final byToken = <String, ArticleImportPreview>{};
    for (final segment in state.analysis.segments) {
      final preview = segment.preview;
      if (segment.status != ArticleSegmentStatus.success || preview == null) {
        continue;
      }
      byToken.putIfAbsent(preview.previewToken, () => preview);
    }
    return byToken.values.toList(growable: false);
  }

  List<ArticleSegmentState> _markBatch(
    ArticleBatch batch, {
    required ArticleSegmentStatus status,
    ArticleImportPreview? preview,
    String? error,
    bool clearPreview = false,
  }) => <ArticleSegmentState>[
    for (final segment in state.analysis.segments)
      if (batch.segmentIds.contains(segment.id))
        segment.copyWith(
          status: status,
          preview: preview,
          error: error,
          clearPreview: clearPreview,
          clearError: !clearPreview,
        )
      else
        segment,
  ];

  /// 合并出的新预览只**追加**勾选，不覆盖用户已经手动取消的选择。
  Set<String> _unionSelection(ArticleImportPreview preview) {
    final current = state.selection.selected;
    final initial = initialSelectionKeys(preview);
    if (current.isEmpty) return initial;
    return <String>{...current, ...initial};
  }

  /// 是否默认「仅看 AI 推荐」。
  ///
  /// 与旧版逐条一致：AI 真的筛过、没有任何短语 / 句子、且推荐词确实比候选少
  /// 时才默认开启——否则会把用户想看的候选全藏起来。
  bool _showRecommendedOnly(ArticleImportPreview preview) {
    final candidates = preview.candidateCount;
    return preview.aiApplied &&
        preview.phraseCount == 0 &&
        preview.sentenceCount == 0 &&
        preview.recommendedTerms.isNotEmpty &&
        preview.recommendedTerms.length < candidates;
  }
}

/// 文章导入向导状态。
final NotifierProvider<ArticleWizardNotifier, ArticleWizardState>
articleWizardProvider =
    NotifierProvider<ArticleWizardNotifier, ArticleWizardState>(
      ArticleWizardNotifier.new,
    );

/// 候选的内容类型对应的筛选档。
ArticleCandidateFilter _filterOf(ArticleCandidate candidate) =>
    switch (candidate.entryType) {
      LexicalContentType.word => ArticleCandidateFilter.word,
      LexicalContentType.phrase => ArticleCandidateFilter.phrase,
      LexicalContentType.sentence => ArticleCandidateFilter.sentence,
    };
