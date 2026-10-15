/// 区间内的数字输入框。
///
/// **为什么不用滑条**：温度、token 上限、超时这几个值用户经常需要精确输入
/// （「就按 5000 算」），滑条给不出这种控制；反过来 `TextField` 会让用户
/// 打出越界的值，被解析层静默夹掉后他看到的仍是自己输入的数字。
/// 这里在**输入时**就夹取并回写文本框，「保存的值」与「看到的值」永远一致。
///
/// **为什么不用 `FilteringTextInputFormatter.allow` 过滤字符**：实测在
/// Flutter 3.47 上它会把整段输入清空——连完全匹配的正则都留不下，
/// 等于这个输入框一个数字都打不出来。改为在 `_handleChanged` 里做校验：
/// 解析不出数字就把文本框恢复成上一个合法值。这条路径还顺带覆盖了
/// 「粘贴了一段无关文字」的情况，而不只是逐键过滤。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 数字输入的合法区间。
typedef NumberBounds = ({num min, num max});

/// 区间内的数字输入框。
class BoundedNumberField extends StatefulWidget {
  /// 以标签、当前值、合法区间与提交回调构造。
  const new({
    required this.label,
    required this.value,
    required this.bounds,
    required this.onCommitted,
    super.key,
  });

  /// 字段标签。
  final String label;

  /// 当前值（来自设置，外部改写时会同步）。
  final num value;

  /// 合法区间。
  final NumberBounds bounds;

  /// 用户输入被夹取到区间内后的回调。
  final ValueChanged<num> onCommitted;

  @override
  State<BoundedNumberField> createState() => _BoundedNumberFieldState();
}

class _BoundedNumberFieldState extends State<BoundedNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: formatNumber(widget.value),
  );

  /// 最近一次提交出去的值，用于分辨「外部改写」与「自己刚提交的」。
  late num _committed = widget.value;

  @override
  void didUpdateWidget(BoundedNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 备份导入 / 恢复默认会从外部改写设置；此时要覆盖文本框。
    // 自己提交的改动不再回写，否则会把用户正在敲的数字抢走。
    if (widget.value != _committed) {
      _committed = widget.value;
      _controller.text = formatNumber(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        hintStyle: LexiType.body.copyWith(
          color: context.lexiColors.tertiaryLabel,
        ),
      ),
      onChanged: _handleChanged,
    );
  }

  /// 把文本解析成数字提交出去；解析不出就恢复上一个合法值。
  void _handleChanged(String text) {
    final parsed = num.tryParse(text.trim());
    if (parsed == null) {
      _controller.text = formatNumber(_committed);
      return;
    }
    final clamped = parsed.clamp(widget.bounds.min, widget.bounds.max);
    if (clamped != parsed) _controller.text = formatNumber(clamped);
    if (clamped == _committed) return;
    _committed = clamped;
    widget.onCommitted(clamped);
  }
}

/// 数字的展示格式：整数不带小数点，小数去掉多余的零（0.20 显示为 0.2）。
///
/// 去掉尾零是为了让「温度 0.2」不显示成「0.20」——用户会以为这是两个不同的值。
String formatNumber(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  final text = value.toStringAsFixed(2);
  return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
}
