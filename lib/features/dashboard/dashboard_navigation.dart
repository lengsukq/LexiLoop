/// 仪表盘的跳转辅助。
///
/// 路由字符串的唯一出处是 [appDestinations]；这里按目的地名称解析路径，
/// 而不是在页面里硬编码 `'/study'`——导航结构变更时不会漏改某处。
///
/// **学习模式的中文名也放在这里**：首页的队列卡片与专项入口都需要
/// 「点了会去哪」这句话，而模式本身由 `lib/app/router.dart` 解析成
/// [StudyMode]。名字、深链、跳转三者放在一起，界面层就不必各自拼
/// `'?mode='` 字符串。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';

/// 学习页在导航表里的目的地名称。
const String studyDestinationLabel = '复习';

/// 按目的地名称取路由路径；找不到时抛出，因为那是导航表被改坏的编程错误。
String destinationPath(String label) {
  for (final destination in appDestinations) {
    if (destination.label == label) return destination.path;
  }
  throw StateError('导航表缺少「$label」目的地');
}

/// 跳转到指定目的地。
void goToDestination(BuildContext context, String label) {
  context.go(destinationPath(label));
}

/// 学习模式的中文名。
///
/// 用「用户在做什么」而不是枚举名（`daily` → 每日综合）：队列卡片里
/// 「错词强化」比「WRONG_WORDS」更容易让人一眼认出那是错词本。
/// 与旧版 `study-client.tsx` 的 `MODE_LABELS` 同源，但首页与学习页共用
/// 这一份，避免两处各写一遍后漂移。
String studyModeLabel(StudyMode mode) => switch (mode) {
  StudyMode.daily => '每日综合',
  StudyMode.newWords => '仅新词',
  StudyMode.dueReview => '到期复习',
  StudyMode.wrongWords => '错词强化',
  StudyMode.listening => '听力专项',
  StudyMode.spelling => '拼写专项',
  StudyMode.sentenceReview => '句子复习',
  StudyMode.aiRecommended => 'AI 推荐',
};

/// 指向某个学习模式的地址（形如 `/study?mode=WRONG_WORDS`）。
///
/// 走 [destinationPath] 而不是写死 `'/study'`：导航表改了路径，
/// 首页的入口会跟着改，不会静默跳到不存在的路由。
String studyModeLocation(StudyMode mode) =>
    '${destinationPath(studyDestinationLabel)}?mode=${mode.wire}';

/// 跳到某个学习模式。
///
/// 用 [GoRouter.go] 而不是 `push`：学习页在沉浸模式下没有返回键，
/// push 出来的页面用户只能靠系统返回手势离开。
void goToStudyMode(BuildContext context, StudyMode mode) {
  context.go(studyModeLocation(mode));
}
