/// 设置页的数据入口。
///
/// **为什么没有「保存」按钮**：这是纯本地应用，没有提交语义。改动即时写入
/// `settings` 表并让 [appSettingsProvider] 失效，用户切走再回来看到的
/// 就是已生效的值。旧版设置页攒了 13 + 8 个回调 props 到最后统一提交，
/// 中间任何一步失败都会丢掉整份改动。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/ui/feedback/messenger.dart';

/// 写入若干设置项并刷新缓存。
///
/// 传 `null` 表示删除该键、回到默认值（由 `SettingsService.update` 定义）。
///
/// **失败必须可见、且要回滚**：下面两件事都是必需的——
///
/// 1. 让 [appSettingsProvider] 失效，UI 于是重新读出**库里真实的旧值**，
///    刚被切过去的开关会自己弹回来，而不是留在一个假装成功的状态里；
/// 2. 弹一条提示说明没保存成功。
///
/// 收敛前这里把异常直接抛给调用方，而十几处调用几乎全是
/// `unawaited(saveSettings(...))`——异常被无声吞掉，用户只会觉得
/// 「这个设置不生效」。把失败处理放在这个唯一的写入口，比要求每个调用点
/// 都写一遍 try/catch 更难漏。
Future<void> saveSettings(WidgetRef ref, Map<String, Object?> changes) async {
  try {
    await ref
        .read(settingsServiceProvider)
        .update(changes, now: DateTime.now().millisecondsSinceEpoch);
  } on Object catch (error) {
    ref.invalidate(appSettingsProvider);
    showAppMessage('设置未保存：${normalizeError(error).message}');
    return;
  }
  ref.invalidate(appSettingsProvider);
}
