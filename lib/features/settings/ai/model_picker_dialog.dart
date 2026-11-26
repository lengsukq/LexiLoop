/// 模型选择对话框（「从 Models 接口获取」的结果）。
///
/// **选择即最终列表**：已有模型默认勾上且可以取消勾选，弹窗返回的集合
/// 直接替换 `models[]`。旧版是并集语义，勾掉一个模型不生效，用户只能删掉
/// 整个 provider 重配——这是同一个缺陷在这里必须换掉的原因。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 选择器的固定宽度：模型多到需要滚动，但不该吃掉整屏。
const double modelPickerWidth = 460;

/// 选择器的固定高度：够放下十几行模型，剩下的滚动。
const double modelPickerHeight = 420;

/// 展示模型选择对话框。
///
/// 返回 `null` 表示取消；返回的列表是「最终应有的模型集合」。
Future<List<String>?> showModelPicker(
  BuildContext context, {
  required String providerLabel,
  required List<String> models,
  required Set<String> initialSelection,
}) => showDialog<List<String>>(
  context: context,
  builder: (dialogContext) => ModelPickerDialog(
    providerLabel: providerLabel,
    models: models,
    initialSelection: initialSelection,
  ),
);

/// 模型多选对话框。
class ModelPickerDialog extends StatefulWidget {
  /// 以来源名称、候选模型与初始勾选集合构造。
  const new({
    required this.providerLabel,
    required this.models,
    required this.initialSelection,
    super.key,
  });

  /// 模型列表的来源（provider 名称）。
  final String providerLabel;

  /// 候选模型。
  final List<String> models;

  /// 初始勾选集合。
  final Set<String> initialSelection;

  @override
  State<ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<ModelPickerDialog> {
  late final Set<String> _selected = <String>{...widget.initialSelection};
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    return AlertDialog(
      title: Text('选择要保留的模型 · ${widget.providerLabel}'),
      content: SizedBox(
        width: modelPickerWidth,
        height: modelPickerHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _toolbar(visible),
            const SizedBox(height: LexiSpace.s8),
            Expanded(child: _list(visible)),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('modelPickerCancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('modelPickerApply'),
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: Text('应用 ${_selected.length} 个'),
        ),
      ],
    );
  }

  Widget _toolbar(List<String> visible) => Row(
    children: <Widget>[
      Expanded(
        child: TextField(
          key: const Key('modelPickerFilter'),
          autofocus: true,
          decoration: const InputDecoration(hintText: '筛选模型名称', isDense: true),
          onChanged: (value) => setState(() => _filter = value),
        ),
      ),
      const SizedBox(width: LexiSpace.s8),
      TextButton(
        key: const Key('modelPickerSelectAll'),
        onPressed: () => setState(() => _selected.addAll(visible)),
        child: const Text('全选新增'),
      ),
      TextButton(
        key: const Key('modelPickerClear'),
        onPressed: () => setState(() => _selected.removeAll(visible)),
        child: const Text('清空'),
      ),
    ],
  );

  Widget _list(List<String> visible) {
    if (visible.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的模型。',
          key: const Key('modelPickerEmpty'),
          style: LexiType.body.copyWith(
            color: context.lexiColors.quaternaryLabel,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final model = visible[index];
        return CheckboxListTile(
          key: Key('modelPickerOption-$model'),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(model, maxLines: 1, overflow: TextOverflow.ellipsis),
          value: _selected.contains(model),
          onChanged: (checked) => setState(() {
            if (checked ?? false) {
              _selected.add(model);
            } else {
              _selected.remove(model);
            }
          }),
        );
      },
    );
  }

  /// 筛选后的候选；筛选串为空时是全部。
  List<String> _visible() {
    final keyword = _filter.trim().toLowerCase();
    if (keyword.isEmpty) return widget.models;
    return widget.models
        .where((model) => model.toLowerCase().contains(keyword))
        .toList();
  }
}
