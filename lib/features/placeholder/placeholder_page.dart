/// 尚未实现的页面的占位。
///
/// P0 阶段只跑通外壳与首页，其余 7 个页面按阶段逐步替换。
/// 占位页明确标注所属阶段，避免被误认为已完成功能——
/// 旧版 `import/page.tsx` 的假进度条（写死 `value={75}`）就是反面教材。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 标注「待实现」的页面占位。
class PlaceholderPage extends StatelessWidget {
  /// 创建占位页。
  const new({required this.destination, super.key});

  /// 该页面所属的导航目的地。
  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(destination.icon, size: 44, color: colors.tertiaryLabel),
              const SizedBox(height: 16),
              Text(
                destination.label,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '此页面将在后续阶段实现',
                style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                destination.path,
                style: TextStyle(
                  color: colors.quaternaryLabel,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
