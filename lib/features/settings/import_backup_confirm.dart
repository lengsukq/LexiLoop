/// 「导入 JSON 备份」的统一移动端底部确认抽屉。
///
/// 导入动作会**整份替换 12 张表**，属于不可逆的高危覆盖操作。
/// 词库页与设置页共用本入口，通过底部确认抽屉（带危险色主按钮与清晰说明）
/// 替代原先繁琐的手输大写 `IMPORT` 弹窗。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';

/// 导入备份确认按钮的稳定 Key。
const Key importBackupConfirmButtonKey = Key('importBackupConfirmButton');

/// 弹出导入备份的确认抽屉；返回是否确认。
Future<bool> confirmBackupImport(BuildContext context) => showLexiConfirmSheet(
  context,
  title: '导入 JSON 备份？',
  body:
      '导入会用备份文件里的内容整体替换当前数据库：'
      '词条、词典内容、学习记录、导入历史与设置都会被覆盖，'
      '当前库中不在备份里的数据将无法找回。\n\n'
      '如果当前库里有尚未备份的数据，请先「导出 JSON 备份」。',
  confirmLabel: '导入并覆盖',
  destructive: true,
  confirmButtonKey: importBackupConfirmButtonKey,
);
