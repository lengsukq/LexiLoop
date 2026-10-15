/// 词库列表页的展示格式化与文案。
///
/// 单独成文件而不是散在各控件里：筛选芯片、下拉框、卡片徽标都要用同一批
/// 名字，改一个状态名时不会只改到一半。
library;

import 'package:lexiloop/domain/enums.dart';

/// 掌握等级的中文名。
String masteryLabel(MasteryLevel level) => switch (level) {
  MasteryLevel.newWord => '新词',
  MasteryLevel.learning => '学习中',
  MasteryLevel.familiar => '熟悉',
  MasteryLevel.proficient => '熟练',
  MasteryLevel.mastered => '已掌握',
};

/// 初始化状态的中文名。
String initializationStatusLabel(InitializationStatus status) =>
    switch (status) {
      InitializationStatus.pending => '待初始化',
      InitializationStatus.queued => '排队中',
      InitializationStatus.running => '初始化中',
      InitializationStatus.ready => '已就绪',
      InitializationStatus.partial => '部分就绪',
      InitializationStatus.failed => '失败',
      InitializationStatus.disabled => '已禁用',
    };

/// 卡片上的到期日，形如 `3 月 1 日`。
///
/// 只显示月日：词条列表关心的是「什么时候要复习」，年份对日常复习没有
/// 决策价值，却会挤掉卡片上真正重要的释义。手写格式化而不引 `intl`，
/// 与 `word_detail_format.dart` 保持同一取舍。
String formatDueDate(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${date.month} 月 ${date.day} 日';
}
