/// 把「撤销失败」的原因整理成一句人话。
///
/// `CsvImportService` 把真正的原因塞进 [AppError.details]：静态不合格时是一句
/// 解释，动态依赖检查时是**一批词条文本**。`AppError.message` 本身只是一个
/// 固定的错误码文案（「该批次无法无损撤销。」），直接弹它等于什么都没说——
/// 用户看到「无法撤销」，却不知道是哪个词条挡住的，下一次只会再试一次。
///
/// 这里只做展示层的拼装，服务层仍只管抛出类型化的错误。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';

/// 撤销类错误码：静态条件不满足，或存在不可逆的依赖。
const Set<AppErrorCode> _rollbackErrorCodes = <AppErrorCode>{
  AppErrorCode.importBatchNotRollbackable,
  AppErrorCode.importBatchHasDependencies,
};

/// 词条列表最多展示多少个。
///
/// 直接复用 [rollbackBlockedTermLimit]：服务层就是按这个数截断的，
/// 这里再截一次是为了兜住详情被别处塞了更长列表的情况。
const int shownRollbackTermLimit = rollbackBlockedTermLimit;

/// 面向用户解释这次撤销为什么被拒。
///
/// 不是撤销类错误、或没有可展示的详情时返回 `null`，由调用方退回
/// [AppError.message]。
String? explainRollbackBlocked(AppError error) {
  if (!_rollbackErrorCodes.contains(error.code)) return null;
  final details = error.details;
  if (details is String && details.isNotEmpty) return details;
  if (details is List) return _joinTerms(details);
  return null;
}

/// 把词条列表拼成「A、B、C 等共 N 个」的一句话；全是空串时返回 `null`。
String? _joinTerms(List<Object?> details) {
  final terms = details
      .map((term) => '$term')
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  if (terms.isEmpty) return null;

  final shown = terms.take(shownRollbackTermLimit).toList(growable: false);
  final hidden = terms.length - shown.length;
  final list = shown.join('、');
  return hidden > 0 ? '$list 等 ${terms.length} 个词条' : list;
}

/// 撤销被拒时展示给用户的完整文案。
String rollbackBlockedMessage(AppError error) {
  final explanation = explainRollbackBlocked(error);
  return explanation == null ? error.message : '${error.message}$explanation';
}

/// 撤销按钮置灰时解释「为什么」。
///
/// 与 [ImportBatchSummary.canRollback] 读同一批字段、判定条件一致，但换成
/// 人话：条件不满足时返回 `null` 的反面是「可以撤销」，此时不需要理由。
/// `canRollback` 守卫测试会把这两者钉在一起，防止文案与判定各说各话。
String? staticRollbackBlockedReason(ImportBatchSummary batch) {
  if (batch.canRollback) return null;
  return switch (batch.status) {
    ImportBatchStatus.pending => '批次尚未提交。',
    ImportBatchStatus.rolledBack => '该批次已经撤销过了。',
    ImportBatchStatus.failed => '该批次导入失败，没有需要撤销的写入。',
    ImportBatchStatus.committed => _committedBlockedReason(batch),
  };
}

/// 已提交批次的静态不合格原因。
String _committedBlockedReason(ImportBatchSummary batch) {
  if (batch.resetLearningProgress) {
    return '该批次重置过已有词条的学习进度，删除的学习历史无法恢复。';
  }
  if (batch.importMode != ImportMode.skipExisting) {
    return '该批次覆盖过已有词条的内容，撤销会把词条删掉。';
  }
  return '该批次改动过已有词条，无法无损撤销。';
}
