/// 「导入 JSON 备份」的统一确认框。
///
/// 这个动作会**整份替换 12 张表**（见 `backup_import.dart` 的注释），是整个
/// 应用里破坏性最强的操作。收拢前它有两个入口，确认强度却完全不同：
///
/// * 设置 › 数据管理：要求打字输入 `IMPORT`；
/// * 词库页头部与空态的「导入备份」：**零确认**，点一下选完文件就覆盖。
///
/// 同一个服务、同一个后果，两套门槛。入口越显眼（词库页就在主按钮旁边）
/// 反而越宽松，这正好是反的。现在两个入口都用这一个对话框。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/settings/typed_confirm_dialog.dart';

/// 要求打字确认的关键词。
const String importConfirmKeyword = 'IMPORT';

/// 弹出导入备份的确认框；返回是否确认。
Future<bool> confirmBackupImport(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => const BackupImportConfirmDialog(),
  );
  return confirmed ?? false;
}

/// 打字确认的「导入 JSON 备份」对话框。
class BackupImportConfirmDialog extends StatelessWidget {
  /// 以默认样式构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const TypedConfirmDialog(
      title: '导入 JSON 备份？',
      body:
          '导入会用备份文件里的内容**整体替换**当前数据库：'
          '词条、词典内容、学习记录、导入历史与设置都会被覆盖，'
          '当前库中不在备份里的数据将无法找回。\n\n'
          '如果当前库里有还没备份过的东西，请先「导出 JSON 备份」。\n\n'
          '请输入 IMPORT 以确认。',
      keyword: importConfirmKeyword,
      confirmLabel: '导入并覆盖',
      keyPrefix: 'importBackupConfirm',
    );
  }
}
