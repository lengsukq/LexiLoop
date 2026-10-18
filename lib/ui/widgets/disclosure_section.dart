/// 渐进展示低频内容；折叠时保持表单和交互状态。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 无额外卡片底板的可展开分区。
class DisclosureSection extends StatefulWidget {
  /// 创建可展开分区。
  const new({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    super.key,
  });

  /// 始终可见的入口名称。
  final String title;

  /// 展开后的内容。
  final Widget child;

  /// 首次显示时是否展开。
  final bool initiallyExpanded;

  @override
  State<DisclosureSection> createState() => _DisclosureSectionState();
}

class _DisclosureSectionState extends State<DisclosureSection> {
  // 展开状态(bool)与内部滚动位置(double)必须使用不同的存储域。
  final PageStorageBucket _contentStorage = PageStorageBucket();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey<String>('disclosure-${widget.title}'),
    title: Text(widget.title, style: LexiType.callout),
    initiallyExpanded: widget.initiallyExpanded,
    maintainState: true,
    childrenPadding: const EdgeInsets.only(bottom: LexiSpace.s12),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      PageStorage(bucket: _contentStorage, child: widget.child),
    ],
  );
}
