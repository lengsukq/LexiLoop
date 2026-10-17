/// 要求敲对一个关键字才放行的确认对话框。
///
/// 导出备份、从远端恢复、清空全部数据共用它：三者的共同点是「一步误点就
/// 不可逆」，而确认成本只需要用户多打几个字母。**为什么值得共用**：这三个
/// 动作的差别只有标题、正文与关键字，各自实现一遍就是三处需要同步的
/// 「禁用逻辑 + key 命名」。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

/// 敲对关键字才放行的确认对话框。
class TypedConfirmDialog extends StatefulWidget {
  /// 以标题、正文、关键字、确认按钮文案与 key 前缀构造。
  const new({
    required this.title,
    required this.body,
    required this.keyword,
    required this.confirmLabel,
    required this.keyPrefix,
    super.key,
  });

  /// 对话框标题。
  final String title;

  /// 正文：必须说清「这一步做什么、不含什么、为什么不可逆」。
  final String body;

  /// 用户需要逐字输入的关键字（大小写敏感）。
  final String keyword;

  /// 确认按钮的文案。
  final String confirmLabel;

  /// widget 测试用的 key 前缀，派生出 `…Field` 与 `…Button` 两个 key。
  ///
  /// 由前缀派生而不是各传一个 key：这些对话框的差别只有标题、正文与关键字，
  /// 让它们各自声明 key 只会多几处需要同步的名字。
  final String keyPrefix;

  /// 输入框的 key。
  Key get fieldKey => Key('${keyPrefix}Field');

  /// 确认按钮的 key。
  Key get buttonKey => Key('${keyPrefix}Button');

  @override
  State<TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<TypedConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _matched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.body),
          const SizedBox(height: LexiSpace.s12),
          TextField(
            key: widget.fieldKey,
            controller: _controller,
            autocorrect: false,
            decoration: InputDecoration(hintText: widget.keyword),
            onChanged: (value) =>
                setState(() => _matched = value.trim() == widget.keyword),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: widget.buttonKey,
          onPressed: _matched ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
