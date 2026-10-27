/// 词条详情页的数据提供者与写操作。
///
/// **取数与渲染分离**：页面组件只 `watch` 这里的数据提供者、只调用
/// [WordDetailActions] 的方法，不直接接触 Drift。旧版详情页把取数放在
/// `use-word-detail.ts`、又在组件里重复了一遍解析逻辑，还向下传了
/// 11 + 6 + 7 个回调 props；这里用「一个数据提供者 + 一个行为对象」收敛。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/related_word_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 单个词条的详情；词条不存在时数据为 `null`。
final FutureProviderFamily<WordDetail?, int> wordDetailProvider =
    FutureProvider.family<WordDetail?, int>(
      (ref, wordId) => ref.watch(wordDetailDaoProvider).find(wordId),
    );

/// 单个词条的复习统计与卡片状态。
final FutureProviderFamily<WordLearningSnapshot, int>
wordLearningSnapshotProvider = FutureProvider.family<WordLearningSnapshot, int>(
  (ref, wordId) => ref.watch(wordDetailDaoProvider).learningSnapshot(wordId),
);

/// 单个词条的最近复习记录。
final FutureProviderFamily<List<ReviewLogEntry>, int> recentReviewLogsProvider =
    FutureProvider.family<List<ReviewLogEntry>, int>(
      (ref, wordId) => ref.watch(wordDetailDaoProvider).recentLogs(wordId),
    );

/// 详情页展示用的首选发音口音。
///
/// 设置尚未加载完成时退回 [Accent.us]，与 `AppSettings.defaults` 一致，
/// 避免详情页的音标先显示英音再跳成美音。
final Provider<Accent> preferredAccentProvider = Provider<Accent>((ref) {
  final settings = ref.watch(appSettingsProvider).value;
  return settings?.playback.defaultAccent ?? Accent.us;
});

/// 详情页当前选中的发音口音（按词条 ID 记忆）。
///
/// **页面级状态而不是全局设置**：旧版详情页把 `selectedAccent` 放在页面
/// 组件的 `useState` 里，切走就没了。这里同样按词条 ID 记忆，但活到
/// 该词条的下一次详情会话为止——回到详情页时音标还是上次选的那一个，
/// 不必每次都重新点一遍英音。
///
/// 用「词条 ID → 口音」的映射而不是 family notifier：Riverpod 3 的
/// family notifier 要拿到参数得读内部 API，而这里的需求就是一张很小的
/// 查表，用 family 换取的「自动 dispose」对这张表毫无价值。
class AccentSelection extends Notifier<Map<int, Accent>> {
  @override
  Map<int, Accent> build() => const <int, Accent>{};

  /// 记住用户在该词条上选过的口音。
  void select(int wordId, Accent accent) =>
      state = <int, Accent>{...state, wordId: accent};
}

/// 详情页口音选择状态。
final NotifierProvider<AccentSelection, Map<int, Accent>>
selectedAccentProvider = NotifierProvider<AccentSelection, Map<int, Accent>>(
  AccentSelection.new,
);

/// 单个词条最近的数据源调用记录（详情页「初始化质量」卡）。
final FutureProviderFamily<List<ProviderAttemptView>, int>
wordProviderAttemptsProvider =
    FutureProvider.family<List<ProviderAttemptView>, int>(
      (ref, wordId) =>
          ref.watch(wordDetailDaoProvider).providerAttempts(wordId),
    );

/// 有道内容的预览与应用服务。
///
/// 词典查询服务在这里单独构造：它是**有状态**的（持有 HTTP 客户端），
/// 复用 `dao_providers` 里的实例会让详情页与初始化队列共用同一份连接池，
/// 而详情页的预览是用户手点触发的、与后台任务无关的一次性调用。
final Provider<WordContentRefreshService> wordContentRefreshServiceProvider =
    Provider<WordContentRefreshService>(
      (ref) => WordContentRefreshService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
        DictionaryLookupAdapter(
          DictionaryLookupService(ref.watch(httpFetcherProvider)),
        ),
        WordEditService(ref.watch(databaseProvider)),
      ),
    );

/// 关联词预览与加入服务。
final Provider<RelatedWordService> relatedWordServiceProvider =
    Provider<RelatedWordService>(
      (ref) => RelatedWordService(ref.watch(databaseProvider)),
    );

/// 词条详情的写操作入口。
final Provider<WordDetailActions> wordDetailActionsProvider =
    Provider<WordDetailActions>(WordDetailActions.new);

/// 词条详情的写操作（暂停、笔记、删除、有道刷新、初始化、关联词）。
///
/// 只有「容器引用」一个依赖，不接收回调参数——行为对象而非回调集合，
/// 是旧版详情页参数膨胀（11 + 6 + 7 个 props）的直接对策。
class WordDetailActions {
  /// 以容器引用构造。
  const new(this._ref);

  final Ref _ref;

  /// 切换「暂停学习」。
  ///
  /// 时间戳在方法内部取：写操作只需要一个「现在」，为它多开一个参数
  /// 只会让每个调用点都要先算一遍当前时间。
  Future<void> setSuspended(int wordId, {required bool suspended}) async {
    final db = _ref.read(databaseProvider);
    await (db.update(db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        isSuspended: Value<bool>(suspended),
        updatedAt: Value<int>(_now()),
      ),
    );
    _invalidateWord(wordId);
  }

  /// 保存笔记；空白内容写回 `null`，避免留下一个「有笔记但看不见」的词条。
  Future<void> saveNote(int wordId, String note) async {
    final text = note.trim();
    final db = _ref.read(databaseProvider);
    await (db.update(db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        userNote: Value<String?>(text.isEmpty ? null : text),
        updatedAt: Value<int>(_now()),
      ),
    );
    _invalidateWord(wordId);
  }

  /// 删除词条。
  ///
  /// 内容、卡片、日志与错词状态由外键 `ON DELETE CASCADE` 一并清除
  /// （`beforeOpen` 里已 `PRAGMA foreign_keys = ON`），因此这里只删 `words`。
  Future<void> delete(int wordId) async {
    final db = _ref.read(databaseProvider);
    await (db.delete(db.words)..where((row) => row.id.equals(wordId))).go();
    _ref
      ..invalidate(wordDetailProvider(wordId))
      ..invalidate(wordLearningSnapshotProvider(wordId))
      ..invalidate(recentReviewLogsProvider(wordId))
      ..invalidate(wordProviderAttemptsProvider(wordId))
      ..invalidate(dashboardOverviewProvider)
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(masterySummaryProvider);
  }

  /// 保存用户手工撰写的释义。
  ///
  /// 释义与例句的写入全部下沉到 [WordEditService]：那里才知道「手工内容」
  /// 的判定规则与 `content_version` 的自增口径，界面层再抄一遍必然漂移。
  Future<void> updateManualDefinition(
    int wordId,
    String definition, {
    String? partOfSpeech,
  }) async {
    await _edit.updateManualDefinition(
      wordId: wordId,
      definition: definition,
      partOfSpeech: partOfSpeech,
      now: _now(),
    );
    _invalidateWord(wordId);
  }

  /// 删除第 [index] 条例句。
  Future<void> deleteExample(int wordId, int index) async {
    await _edit.deleteExample(wordId: wordId, index: index, now: _now());
    _invalidateWord(wordId);
  }

  /// 为第 [index] 条例句排一个 AI 翻译任务。
  ///
  /// 入队即返回：真正翻譯由 worker 在后台做，界面不该为了等一句译文
  /// 把按钮按住——用户连点十几句也只会有一个活跃任务（部分唯一索引保证）。
  Future<void> translateExample(int wordId, int index) async {
    await _edit.translateExample(wordId: wordId, index: index, now: _now());
  }

  /// 请求生成（或重新生成）助记法。
  Future<void> requestMnemonic(int wordId) async {
    await _edit.enqueueInitialization(
      wordId: wordId,
      now: _now(),
      taskType: JobTaskType.mnemonic,
    );
  }

  /// 排一个初始化任务。
  ///
  /// 「补全缺失内容」传 [InitializationMode.fillMissingFields]，
  /// 「重新生成」传 [InitializationMode.forceOverwrite]；已有活跃任务时
  /// [WordEditService.enqueueInitialization] 会按「更强的模式胜出」升级它，
  /// 因此重复点击不会丢掉用户最后表达的那次意图。
  Future<void> requestInitialization(
    int wordId,
    InitializationMode mode,
  ) async {
    await _edit.enqueueInitialization(wordId: wordId, now: _now(), mode: mode);
    _invalidateAfterQueueChange(wordId);
  }

  /// 排一个「翻译补全」任务。
  ///
  /// 一个任务同时补齐缺失的释义译文、摘要译文与例句译文
  /// （见 `LlmSupplementalTaskRunner`）：三者是同一件事的三个部分，
  /// 拆成三个任务只会让用户在一个词条上看到三条排队记录。
  Future<void> requestTranslation(int wordId) async {
    await _edit.enqueueInitialization(
      wordId: wordId,
      now: _now(),
      taskType: JobTaskType.exampleTranslations,
    );
    _invalidateAfterQueueChange(wordId);
  }

  /// 抓取有道内容预览（**不写库**）。
  Future<YoudaoPreviewResult> previewYoudao(
    int wordId, {
    String? termOverride,
  }) => _refresh.preview(wordId: wordId, termOverride: termOverride);

  /// 应用有道预览内容；[newTerm] 非空时同时改词条文本。
  Future<void> applyYoudao({
    required int wordId,
    required DictionaryContent content,
    required InitializationMode mode,
    required List<ProviderAttemptRecord> attempts,
    String? newTerm,
  }) async {
    await _refresh.apply(
      wordId: wordId,
      fetched: content,
      mode: mode,
      attempts: attempts,
      now: _now(),
      newTerm: newTerm,
    );
    _invalidateAfterQueueChange(wordId);
  }

  /// 预览一个关联词在父词条里的关系信息与词库状态。
  Future<RelatedWordPreview> previewRelatedWord(
    int parentWordId,
    String term,
  ) => _related.preview(parentWordId: parentWordId, rawTerm: term);

  /// 把关联词加入词库（必要时同时排初始化任务）。
  Future<RelatedAddResult> addRelatedWord({
    required int parentWordId,
    required String term,
    required RelationType relation,
  }) async {
    final result = await _related.add(
      parentWordId: parentWordId,
      rawTerm: term,
      relation: relation,
      now: _now(),
    );
    _invalidateList();
    return result;
  }

  /// 本次写入用的服务实例。
  ///
  /// 刻意不引用 `features/add` 里的 provider：详情页与「添加词条」弹窗
  /// 是两条独立的入口，共享一个 provider 会让任一侧重构都要看另一侧。
  WordEditService get _edit => WordEditService(_ref.read(databaseProvider));

  /// 有道刷新服务。
  WordContentRefreshService get _refresh =>
      _ref.read(wordContentRefreshServiceProvider);

  /// 关联词服务。
  RelatedWordService get _related => _ref.read(relatedWordServiceProvider);

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 失效该词条相关的全部缓存。
  ///
  /// 同时失效仪表盘概览：暂停与删除都会改变「今日到期」「新词可用」，
  /// 若只刷新详情页，用户切回首页会看到过期数字。
  void _invalidateWord(int wordId) {
    _ref
      ..invalidate(wordDetailProvider(wordId))
      ..invalidate(wordLearningSnapshotProvider(wordId))
      ..invalidate(recentReviewLogsProvider(wordId))
      ..invalidate(wordProviderAttemptsProvider(wordId))
      ..invalidate(dashboardOverviewProvider);
  }

  /// 入队或应用内容之后失效词条与列表两侧的缓存。
  ///
  /// 列表侧必须一起失效：词条文本、初始化状态与掌握分都在卡片上，
  /// 只刷新详情页会让用户返回列表时看到一个「还没改」的旧词条。
  void _invalidateAfterQueueChange(int wordId) {
    _invalidateWord(wordId);
    _invalidateList();
  }

  /// 失效词库列表相关的缓存。
  void _invalidateList() {
    _ref
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(masterySummaryProvider);
  }
}
