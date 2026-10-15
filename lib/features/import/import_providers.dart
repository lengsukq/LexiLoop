/// 导入向导的状态与数据提供者。
///
/// 向导的每一步都写进一个不可变状态，而不是散在多个 `setState` 里——
/// 旧版 `import/page.tsx` 用 9 个 useState 表达同一件事，中途刷新页面
/// 就会丢失「已选语言但还没选文件」这类上下文。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/csv_import_service.dart';

/// 可选的词条语言。
class ImportLanguage {
  /// 以语言代码与显示名构造。
  const new(this.code, this.label);

  /// ISO 639-1 代码（与 `words.source_language` 一致）。
  final String code;

  /// 中文显示名。
  final String label;
}

/// 导入时可选的语言。
///
/// 与 `core/constants.dart` 的小写语言族、以及 TTS 语言表覆盖的集合一致，
/// 避免出现「能导入但读不出声」的组合。
const List<ImportLanguage> importLanguages = <ImportLanguage>[
  ImportLanguage('en', '英语'),
  ImportLanguage('zh', '中文'),
  ImportLanguage('ja', '日语'),
  ImportLanguage('ko', '韩语'),
  ImportLanguage('fr', '法语'),
  ImportLanguage('de', '德语'),
  ImportLanguage('es', '西班牙语'),
  ImportLanguage('it', '意大利语'),
  ImportLanguage('pt', '葡萄牙语'),
  ImportLanguage('ru', '俄语'),
  ImportLanguage('nl', '荷兰语'),
  ImportLanguage('sv', '瑞典语'),
  ImportLanguage('da', '丹麦语'),
  ImportLanguage('no', '挪威语'),
];

/// 源语言的默认值。
const String defaultSourceLanguage = 'en';

/// 目标语言的默认值。
const String defaultTargetLanguage = 'zh';

/// CSV 导入服务。
final Provider<CsvImportService> csvImportServiceProvider =
    Provider<CsvImportService>(
      (ref) => CsvImportService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
      ),
    );

/// 导入向导的状态。
class ImportWizardState {
  /// 以各字段构造。
  const new({
    this.sourceLanguage = defaultSourceLanguage,
    this.targetLanguage = defaultTargetLanguage,
    this.preview,
    this.mode = ImportMode.skipExisting,
    this.onlyProblems = false,
    this.busy = false,
    this.errorMessage,
    this.result,
  });

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 当前预览（未选文件时为 `null`）。
  final ImportPreview? preview;

  /// 选中的导入模式。
  final ImportMode mode;

  /// 预览表格是否只看问题行。
  final bool onlyProblems;

  /// 是否有正在进行的异步操作。
  final bool busy;

  /// 面向用户的错误信息。
  final String? errorMessage;

  /// 最近一次提交的结果。
  final ImportCommitResult? result;

  /// 是否已解析出预览。
  bool get hasPreview => preview != null;

  /// 复制一份并替换给定字段。
  ///
  /// 可空字段用 `clearXxx` 显式清空：`copyWith(preview: null)` 无法区分
  /// 「不改」与「置空」，这是 Dart 里最常见的 copyWith 陷阱。
  ImportWizardState copyWith({
    String? sourceLanguage,
    String? targetLanguage,
    ImportPreview? preview,
    bool clearPreview = false,
    ImportMode? mode,
    bool? onlyProblems,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
    ImportCommitResult? result,
    bool clearResult = false,
  }) {
    return ImportWizardState(
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      preview: clearPreview ? null : (preview ?? this.preview),
      mode: mode ?? this.mode,
      onlyProblems: onlyProblems ?? this.onlyProblems,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      result: clearResult ? null : (result ?? this.result),
    );
  }
}

/// 导入向导的状态管理器。
class ImportWizardNotifier extends Notifier<ImportWizardState> {
  @override
  ImportWizardState build() => const ImportWizardState();

  /// 当前时间（epoch 毫秒）。由调用点注入，便于将来替换为可控时钟。
  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// 切换源语言；已解析的预览随语言变化失效。
  void setSourceLanguage(String code) {
    if (code == state.sourceLanguage) return;
    state = state.copyWith(
      sourceLanguage: code,
      clearPreview: true,
      clearResult: true,
      clearError: true,
    );
  }

  /// 切换目标语言；已解析的预览随语言变化失效。
  void setTargetLanguage(String code) {
    if (code == state.targetLanguage) return;
    state = state.copyWith(
      targetLanguage: code,
      clearPreview: true,
      clearResult: true,
      clearError: true,
    );
  }

  /// 切换导入模式。
  void setMode(ImportMode mode) => state = state.copyWith(mode: mode);

  /// 切换「只看问题行」。
  void setOnlyProblems({required bool value}) =>
      state = state.copyWith(onlyProblems: value);

  /// 选择文件并解析预览。
  ///
  /// 用户取消选择不是错误，静默回到原状态——否则每次点开又关掉文件
  /// 对话框都会弹一条「请选择 EasyDict CSV 文件」。
  Future<void> pickFile() async {
    state = state.copyWith(busy: true, clearError: true, clearResult: true);
    try {
      final preview = await ref
          .read(csvImportServiceProvider)
          .preview(
            sourceLanguage: state.sourceLanguage,
            targetLanguage: state.targetLanguage,
            now: _now(),
          );
      state = state.copyWith(preview: preview, busy: false);
    } on AppError catch (error) {
      final cancelled = error.code == AppErrorCode.csvRequired;
      state = state.copyWith(
        busy: false,
        errorMessage: error.message,
        clearError: cancelled,
      );
    }
  }

  /// 提交当前预览。
  Future<void> commit() async {
    final preview = state.preview;
    if (preview == null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await ref
          .read(csvImportServiceProvider)
          .commit(batchId: preview.batchId, mode: state.mode, now: _now());
      state = state.copyWith(busy: false, result: result, clearPreview: true);
      ref.invalidate(importHistoryProvider);
    } on AppError catch (error) {
      state = state.copyWith(busy: false, errorMessage: error.message);
    }
  }

  /// 回到「未选文件」的初始状态。
  void reset() => state = ImportWizardState(
    sourceLanguage: state.sourceLanguage,
    targetLanguage: state.targetLanguage,
  );
}

/// 导入向导状态。
final NotifierProvider<ImportWizardNotifier, ImportWizardState>
importWizardProvider =
    NotifierProvider<ImportWizardNotifier, ImportWizardState>(
      ImportWizardNotifier.new,
    );

/// 最近的导入批次。
final FutureProvider<List<ImportBatchSummary>> importHistoryProvider =
    FutureProvider<List<ImportBatchSummary>>(
      (ref) => ref.watch(csvImportServiceProvider).recentBatches(),
    );

/// 某个批次的行明细（按批次 ID 缓存）。
final FutureProviderFamily<List<ImportRowSummary>, int>
importBatchRowsProvider = FutureProvider.family<List<ImportRowSummary>, int>(
  (ref, batchId) => ref
      .watch(csvImportServiceProvider)
      .batchRows(batchId, limit: importRowPageSize, offset: 0),
);
