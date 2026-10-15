/// 「重置已有词条的学习进度」勾选项。
///
/// **为什么抽到 `lib/ui/widgets/`**：CSV 导入与文章导入都要这一个开关，
/// 旧版两处也是各自渲染同一段 JSX（`components/add/csv-tab.tsx` 与
/// `article-tab.tsx:526`）。它是整个应用里唯一一个会**删除既有学习数据**的
/// 开关，文案、配色与「必须与模式选择在视觉上分开」的做法都不该有两份。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 标题文案。
const String resetProgressTitle = '重置已有词条的学习进度';

/// 说明文案：写清删什么、不删什么、影响范围。
///
/// 三件事缺一不可——用户点下这个开关时最需要知道的正是这三条。
const String resetProgressDescription =
    '删除复习卡、复习日志、错词状态与掌握度，并撤下正在进行的'
    '复习题目。词典内容不删除，但这些学习历史无法恢复。'
    '本次新增的词条不受影响。';

/// 勾选框的间距。
const double _resetOptionGap = 4;

/// 内边距。
const double _resetOptionPadding = 12;

/// 危险色描边的勾选项。
class ResetProgressOption extends StatelessWidget {
  /// 以当前值与回调构造。
  const new({required this.value, required this.onChanged, super.key});

  /// 是否勾选。
  final bool value;

  /// 勾选状态变化。
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      padding: const EdgeInsets.all(_resetOptionPadding),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Checkbox(
            key: const Key('resetLearningProgress'),
            value: value,
            onChanged: (next) => onChanged(next ?? false),
          ),
          const SizedBox(width: _resetOptionGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  resetProgressTitle,
                  style: TextStyle(
                    color: colors.danger,
                    fontSize: LexiType.body.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LexiSpace.s2),
                Text(
                  resetProgressDescription,
                  style: TextStyle(
                    color: colors.secondaryLabel,
                    fontSize: LexiType.footnote.fontSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
