/// 手动添加页「词典批量预览」的状态与数据提供者。
///
/// **为什么与 `add_providers.dart` 的离线手填状态分开**：离线表单不依赖
/// 网络，是弱网/无网络时唯一能建词条的入口；批量预览每一行都要打一次词典。
/// 两者的忙碌标记、失败语义与重置时机都不同，挤进同一个 Notifier 会让
/// 「离线可用」这条底线被网络状态污染。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/add_providers.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/manual_preview_service.dart';

/// 手动预览服务。
final Provider<ManualPreviewService> manualPreviewServiceProvider =
    Provider<ManualPreviewService>((ref) {
      final lookup = DictionaryLookupService(ref.watch(httpFetcherProvider));
      return ManualPreviewService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
        lookup.lookup,
        ref.watch(wordEditServiceProvider),
      );
    });

/// 批量预览可选的语言代码。
///
/// 只有这 7 项，与旧版 `components/add/manual-tab.tsx` 的两个下拉一致——
/// 比手填表单的 12 项窄：批量路径的定位是「快速补一批常见语种的词」，
/// 语种列表越长，逐行确认时的选择成本越高。
const List<String> manualBatchLanguageCodes = <String>[
  'en',
  'zh-CN',
  'ja',
  'ko',
  'fr',
  'de',
  'es',
];

/// 语言代码的中文名；未知代码回落到代码本身。
String manualBatchLanguageLabel(String code) =>
    supportedLanguages[code] ?? code;

/// 预览相关错误的中文提示。
///
/// 服务把可操作原因写进 [AppError.details]（见
/// `services/manual_preview_service.dart` 的库级说明），这里优先取它——
/// 与 `features/import/rollback_blocked_message.dart` 同一约定。
String manualPreviewMessage(AppError error) {
  final details = error.details;
  if (details is String && details.isNotEmpty) return details;
  return error.message;
}

/// 批量预览里的一行。
class ManualBatchRow {
  /// 以各字段构造。
  const new({
    required this.term,
    this.preview,
    this.error = '',
    this.confirmedWordId,
  });

  /// 该行的词条文本。
  final String term;

  /// 预览结果；失败或尚未完成时为 `null`。
  final ManualPreview? preview;

  /// 该行的失败原因（单行失败不影响其他行）。
  final String error;

  /// 已确认后的词条 ID；`null` 表示尚未确认。
  final int? confirmedWordId;

  /// 是否已确认落库。
  bool get isConfirmed => confirmedWordId != null;

  /// 是否「有预览但还没确认」。
  bool get isPending => preview != null && !isConfirmed;

  /// 复制并覆盖部分字段。
  ManualBatchRow copyWith({
    ManualPreview? preview,
    String? error,
    int? confirmedWordId,
  }) => ManualBatchRow(
    term: term,
    preview: preview ?? this.preview,
    error: error ?? this.error,
    confirmedWordId: confirmedWordId ?? this.confirmedWordId,
  );
}

/// 批量预览面板的状态。
class ManualBatchState {
  /// 以各字段构造。
  const new({
    this.text = '',
    this.contentType,
    this.sourceLanguage = defaultSourceLanguage,
    this.targetLanguage = defaultTargetLanguage,
    this.rows = const <ManualBatchRow>[],
    this.previewing = false,
    this.confirming = false,
    this.previewDone = 0,
    this.error,
    this.expandedIndex,
  });

  /// 多行输入文本（每行一个词条）。
  final String text;

  /// 内容类型；`null` 表示「自动判断」（旧版 `TypeChoice = "AUTO"`）。
  final LexicalContentType? contentType;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 逐行结果。
  final List<ManualBatchRow> rows;

  /// 是否正在逐行生成预览。
  final bool previewing;

  /// 是否正在逐行确认。
  final bool confirming;

  /// 已完成的预览行数（用于进度提示）。
  final int previewDone;

  /// 面板级错误（上限、确认失败等）。
  final String? error;

  /// 当前展开详情的行下标。
  final int? expandedIndex;

  /// 是否已有逐行结果。
  bool get hasBatch => rows.isNotEmpty;

  /// 是否有正在进行的异步操作。
  bool get busy => previewing || confirming;

  /// 拿到预览的行数。
  int get successCount => rows.where((row) => row.preview != null).length;

  /// 有预览但尚未确认的行数。
  int get pendingCount => rows.where((row) => row.isPending).length;

  /// 是否全部确认完成。
  bool get allConfirmed => successCount > 0 && pendingCount == 0;

  /// 复制并覆盖部分字段。
  ///
  /// 可空字段用 `clearXxx` 显式置空：`copyWith(contentType: null)` 无法区分
  /// 「不改」与「改成自动判断」。
  ManualBatchState copyWith({
    String? text,
    LexicalContentType? contentType,
    bool clearContentType = false,
    String? sourceLanguage,
    String? targetLanguage,
    List<ManualBatchRow>? rows,
    bool? previewing,
    bool? confirming,
    int? previewDone,
    String? error,
    bool clearError = false,
    int? expandedIndex,
    bool clearExpanded = false,
  }) => ManualBatchState(
    text: text ?? this.text,
    contentType: clearContentType ? null : (contentType ?? this.contentType),
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    rows: rows ?? this.rows,
    previewing: previewing ?? this.previewing,
    confirming: confirming ?? this.confirming,
    previewDone: previewDone ?? this.previewDone,
    error: clearError ? null : (error ?? this.error),
    expandedIndex: clearExpanded ? null : (expandedIndex ?? this.expandedIndex),
  );
}

/// 批量预览的状态管理器。
class ManualBatchController extends Notifier<ManualBatchState> {
  @override
  ManualBatchState build() => const ManualBatchState();

  /// 当前时间（epoch 毫秒）。由调用点注入，便于将来替换为可控时钟。
  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 覆盖输入文本。
  ///
  /// 顺带清掉已有结果：行数与顺序都可能变，留着旧结果会让「第 3 行」
  /// 指向另一个词（旧版同样在 `onChange` 里 `reset()`）。
  void setText(String value) => state = state.copyWith(
    text: value,
    rows: const <ManualBatchRow>[],
    clearError: true,
    clearExpanded: true,
  );

  /// 覆盖内容类型；传 `null` 表示自动判断。
  void setContentType(LexicalContentType? value) => state = value == null
      ? state.copyWith(clearContentType: true)
      : state.copyWith(contentType: value);

  /// 覆盖源语言。
  void setSourceLanguage(String code) =>
      state = state.copyWith(sourceLanguage: code);

  /// 覆盖目标语言。
  void setTargetLanguage(String code) =>
      state = state.copyWith(targetLanguage: code);

  /// 展开 / 收起某一行的详情。
  void toggleExpanded(int index) {
    if (state.expandedIndex == index) {
      state = state.copyWith(clearExpanded: true);
      return;
    }
    state = state.copyWith(expandedIndex: index);
  }

  /// 逐行生成预览（并发上限见 [manualBatchPreviewConcurrency]）。
  ///
  /// 单行失败只写在该行上，不影响其他行；上限不合规时整体拒绝并给出文案。
  Future<void> preview() async {
    if (_rejectOverLimit()) return;
    final lines = manualBatchLines(state.text);
    if (lines.isEmpty) return;
    final service = ref.read(manualPreviewServiceProvider);
    final type = state.contentType;
    final source = state.sourceLanguage;
    final target = state.targetLanguage;
    state = state.copyWith(
      rows: <ManualBatchRow>[
        for (final term in lines) ManualBatchRow(term: term),
      ],
      previewing: true,
      clearError: true,
      previewDone: 0,
      clearExpanded: true,
    );
    await runWithConcurrency<String>(
      lines,
      limit: manualBatchPreviewConcurrency,
      task: (term, index) => _previewLine(
        service: service,
        term: term,
        index: index,
        type: type,
        source: source,
        target: target,
      ),
    );
    state = lines.length == 1
        ? state.copyWith(previewing: false, expandedIndex: 0)
        : state.copyWith(previewing: false, clearExpanded: true);
  }

  /// 输入超出上限时写回错误并清空结果，返回 `true` 表示应放弃这次预览。
  bool _rejectOverLimit() {
    final limitError = manualBatchLimitError(state.text);
    if (limitError == null) return false;
    state = state.copyWith(
      error: limitError,
      rows: const <ManualBatchRow>[],
      clearExpanded: true,
    );
    return true;
  }

  /// 生成一行预览并写回该行。
  Future<void> _previewLine({
    required ManualPreviewService service,
    required String term,
    required int index,
    required LexicalContentType? type,
    required String source,
    required String target,
  }) async {
    try {
      final preview = await service.createPreview(
        text: term,
        sourceLanguage: source,
        sourceLanguageName: manualBatchLanguageLabel(source),
        targetLanguage: target,
        targetLanguageName: manualBatchLanguageLabel(target),
        contentType: type,
        now: _now(),
      );
      _updateRow(index, (row) => row.copyWith(preview: preview));
    } on AppError catch (error) {
      _updateRow(
        index,
        (row) => row.copyWith(error: manualPreviewMessage(error)),
      );
    } finally {
      state = state.copyWith(previewDone: state.previewDone + 1);
    }
  }

  /// 确认某一行。
  Future<void> confirmRow(int index) async {
    if (state.confirming) return;
    state = state.copyWith(confirming: true, clearError: true);
    await _confirmAt(index);
    state = state.copyWith(confirming: false);
  }

  /// 依次确认所有「有预览且未确认」的行。
  ///
  /// 逐行串行而不是并发：确认会写词库，且同一批次里可能有重复词条
  /// （两行同一个词），串行能让第二行走「合并进已有词条」的路径。
  Future<void> confirmAll() async {
    if (state.confirming) return;
    final pending = <int>[
      for (var i = 0; i < state.rows.length; i += 1)
        if (state.rows[i].isPending) i,
    ];
    if (pending.isEmpty) return;
    state = state.copyWith(confirming: true, clearError: true);
    for (final index in pending) {
      await _confirmAt(index);
    }
    state = state.copyWith(confirming: false);
  }

  /// 确认单行；失败只记在面板上，不中断「全部确认」的后续行。
  Future<void> _confirmAt(int index) async {
    final row = _rowAt(index);
    final preview = row?.preview;
    if (row == null || preview == null || row.isConfirmed) return;
    try {
      final result = await ref
          .read(manualPreviewServiceProvider)
          .confirmPreview(previewToken: preview.previewToken, now: _now());
      _updateRow(
        index,
        (item) => item.copyWith(confirmedWordId: result.wordId),
      );
    } on AppError catch (error) {
      state = state.copyWith(
        error: '确认“${row.term}”失败：${manualPreviewMessage(error)}',
      );
    }
  }

  /// 清空文本、逐行结果与展开状态；保留语言与内容类型的选择。
  ///
  /// 保留语言是旧版「继续添加」的行为：同一批人通常连着补同一个语种的词。
  void reset() => state = ManualBatchState(
    sourceLanguage: state.sourceLanguage,
    targetLanguage: state.targetLanguage,
    contentType: state.contentType,
  );

  ManualBatchRow? _rowAt(int index) {
    if (index < 0 || index >= state.rows.length) return null;
    return state.rows[index];
  }

  void _updateRow(int index, ManualBatchRow Function(ManualBatchRow) update) {
    final row = _rowAt(index);
    if (row == null) return;
    final rows = <ManualBatchRow>[...state.rows];
    rows[index] = update(row);
    state = state.copyWith(rows: rows);
  }
}

/// 批量预览状态。
final NotifierProvider<ManualBatchController, ManualBatchState>
manualBatchProvider = NotifierProvider<ManualBatchController, ManualBatchState>(
  ManualBatchController.new,
);
