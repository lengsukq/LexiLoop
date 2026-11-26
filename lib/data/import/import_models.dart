/// 导入功能的传输模型与展示常量。
///
/// 放在 `lib/data/` 而不是 `lib/features/`：这些模型是服务层的返回类型，
/// 页面只是消费者。若放在 feature 下，服务层就要反向依赖 UI 层。
library;

import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/domain/enums.dart';

/// 「导入历史」一次展示的批次数。
///
/// 与旧版 `app/imports/page.tsx` 的 `limit: 20` 一致。

/// 批次行明细分页的每页条数。

/// 预览表格最多渲染的行数。
///
/// 旧版 `import/page.tsx` 取 `slice(0, 200)`：一次渲染两万行会让
/// 列表首帧就卡住，而用户真正要看的只是前几十行与「有没有问题行」。

/// 一次预览的完整结果。
class ImportPreview {
  /// 以各字段构造。
  const new({
    required this.batchId,
    required this.filename,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.createdAt,
    required this.expiresAt,
    required this.rows,
    required this.skippedCount,
  });

  /// 批次 ID（已写入 `import_batches`）。
  final int batchId;

  /// 源文件名。
  final String filename;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 预览创建时间（epoch 毫秒）。
  final int createdAt;

  /// 预览过期时间（epoch 毫秒）。
  final int expiresAt;

  /// 解析出的行（含非法行与重复行）。
  final List<ParsedCsvRow> rows;

  /// 被跳过的完全空行数。
  final int skippedCount;

  /// 数据行总数。
  int get totalRows => rows.length;

  /// 非法行数。
  int get invalidRows =>
      rows.where((row) => row.status == ImportRowStatus.invalid).length;

  /// 文件内重复行数。
  int get duplicateRows =>
      rows.where((row) => row.status == ImportRowStatus.duplicate).length;

  /// 与库中已有词条重复的行数。
  int get existingRows =>
      rows.where((row) => row.status == ImportRowStatus.existing).length;

  /// 可新增的行数。
  int get newRows =>
      rows.where((row) => row.status == ImportRowStatus.newWord).length;

  /// 提交时会真正处理的行数（不含非法与重复）。
  int get importableRows => totalRows - invalidRows - duplicateRows;
}

/// 一次提交的结果摘要。
class ImportCommitResult {
  /// 以各计数构造。
  const new({
    required this.batchId,
    required this.created,
    required this.existing,
    required this.duplicate,
    required this.invalid,
    required this.failed,
    required this.queuedInitializations,
  });

  /// 批次 ID。
  final int batchId;

  /// 新增词条数。
  final int created;

  /// 命中已有词条数（按 [ImportMode] 决定跳过、补字段或覆盖）。
  final int existing;

  /// 文件内重复而跳过的行数。
  final int duplicate;

  /// 非法行数。
  final int invalid;

  /// 提交过程中失败的行数。
  final int failed;

  /// 入队的初始化任务数。
  final int queuedInitializations;

  /// 总行数。
  int get totalRows => created + existing + duplicate + invalid + failed;
}

/// 批次摘要（导入历史列表用）。
class ImportBatchSummary {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.filename,
    required this.status,
    required this.importMode,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.createdWords,
    required this.existingWords,
    required this.queuedInitializations,
    required this.createdAt,
    required this.resetLearningProgress,
    this.completedAt,
    this.rolledBackAt,
  });

  /// 批次 ID。
  final int id;

  /// 源文件名。
  final String filename;

  /// 批次状态。
  final ImportBatchStatus status;

  /// 提交时使用的导入模式。
  final ImportMode importMode;

  /// 数据行总数。
  final int totalRows;

  /// 合法行数。
  final int validRows;

  /// 非法行数。
  final int invalidRows;

  /// 文件内重复行数。
  final int duplicateRows;

  /// 新增词条数。
  final int createdWords;

  /// 命中已有词条数。
  final int existingWords;

  /// 入队初始化任务数。
  final int queuedInitializations;

  /// 提交时是否勾选了「重置已有词条的学习进度」。
  final bool resetLearningProgress;

  /// 创建时间（epoch 毫秒）。
  final int createdAt;

  /// 提交完成时间。
  final int? completedAt;

  /// 撤销时间。
  final int? rolledBackAt;

  /// 是否仍未提交。
  bool get isPending => status == ImportBatchStatus.pending;

  /// 是否可无损撤销。
  ///
  /// 必须与 `CsvImportService._assertStaticEligibility` 的四个条件**逐条相同**：
  /// 已提交 + 仅新增 + 未重置学习进度 + 未改动已有词条。少一条，按钮就会亮起
  /// 然后被服务层拒绝——用户看到的是「按钮能点，但一按就报错」，
  /// 比一开始就置灰更难信任。
  ///
  /// 真正的依赖检查（复习日志、错词、会话引用）在服务层执行，
  /// 此处只做静态判断，用于提前禁用按钮。
  bool get canRollback =>
      status == ImportBatchStatus.committed &&
      importMode == ImportMode.skipExisting &&
      !resetLearningProgress &&
      existingWords == 0;
}

/// 批次中的一行摘要（明细列表用）。
class ImportRowSummary {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.rowNumber,
    required this.term,
    required this.status,
    this.errorMessage,
    this.wordId,
  });

  /// 行 ID。
  final int id;

  /// 数据行序号（从 1 起）。
  final int rowNumber;

  /// 词条文本（解析失败时为空串）。
  final String term;

  /// 处理状态。
  final ImportRowStatus status;

  /// 错误信息。
  final String? errorMessage;

  /// 关联的词条 ID（撤销后为 `null`）。
  final int? wordId;
}
