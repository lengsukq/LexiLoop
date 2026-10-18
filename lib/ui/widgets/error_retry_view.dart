/// 加载失败时的「原因 + 重试」占位。
///
/// **为什么抽出来**：设置页、词库页、词条详情页各写了一份逐字相同的实现
/// （旧版是三处 JSX）。这不是「看起来像」而是「完全一样」——图标、
/// 间距、文案样式、按钮文字全同。三份拷贝意味着改一次间距要改三个地方，
/// 而漏掉的那一个只有在用户恰好走进那条路径时才会被发现。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 外边距。
const double _errorViewPadding = 32;

/// 图标尺寸。
const double _errorIconSize = 40;

/// 图标与文案的间距。
const double _errorIconGap = 12;

/// 文案与按钮的间距。
const double _errorButtonGap = 14;

/// 重试按钮的文案。
const String retryLabel = '重试';

/// 居中的加载失败提示，带一个重试按钮。
class ErrorRetryView extends StatelessWidget {
  /// 以失败原因与重试回调构造。
  const new({required this.message, required this.onRetry, super.key});

  /// 面向用户的失败原因（已是中文，可直接展示）。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(_errorViewPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              LucideIcons.circleAlert,
              size: _errorIconSize,
              color: colors.danger,
            ),
            const SizedBox(height: _errorIconGap),
            Text(
              message,
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: _errorButtonGap),
            FilledButton(onPressed: onRetry, child: const Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
