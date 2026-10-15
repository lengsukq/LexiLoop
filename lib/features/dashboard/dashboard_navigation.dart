/// 仪表盘的跳转辅助。
///
/// 路由字符串的唯一出处是 [appDestinations]；这里按目的地名称解析路径，
/// 而不是在页面里硬编码 `'/study'`——导航结构变更时不会漏改某处。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';

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
