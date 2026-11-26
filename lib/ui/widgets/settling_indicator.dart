/// 会话结算中的占位提示。
///
/// **为什么抽出来**：配对与音标训练的结算阶段需要一段完全相同的提示
/// （转圈 + 「正在结算…」），两处各写一份必然在字号、间距或文案上漂移。
/// 旧版是把这段 JSX 在 `match/page.tsx` 与 `phonetics/page.tsx` 里各写一遍。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 结算中的提示文案。
const String settlingMessage = '正在结算…';

/// 转圈与说明文字的间距。
const double _settlingGap = 14;

/// 结算中的居中提示。
class SettlingIndicator extends StatelessWidget {
  /// 构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: _settlingGap),
          Text(
            settlingMessage,
            style: LexiType.body.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}
