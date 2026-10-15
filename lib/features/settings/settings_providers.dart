/// 设置页的数据入口。
///
/// **为什么没有「保存」按钮**：这是纯本地应用，没有提交语义。改动即时写入
/// `settings` 表并让 [appSettingsProvider] 失效，用户切走再回来看到的
/// 就是已生效的值。旧版设置页攒了 13 + 8 个回调 props 到最后统一提交，
/// 中间任何一步失败都会丢掉整份改动。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';

/// 写入若干设置项并刷新缓存。
///
/// 传 `null` 表示删除该键、回到默认值（由 `SettingsService.update` 定义）。
Future<void> saveSettings(WidgetRef ref, Map<String, Object?> changes) async {
  await ref
      .read(settingsServiceProvider)
      .update(changes, now: DateTime.now().millisecondsSinceEpoch);
  ref.invalidate(appSettingsProvider);
}
