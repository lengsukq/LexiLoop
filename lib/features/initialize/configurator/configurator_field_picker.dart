/// 内容字段勾选区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_fields.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 按分组勾选要补全的内容字段。
///
/// **字段范围不是拍脑袋定的**：这里的每一项都对应某个 provider 能力表里的
/// 一个键（见 [initializationFieldLabels] 的来源说明），
/// 管线填不出来的字段没有出现在这里。
class ConfiguratorFieldPicker extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(
      configuratorProvider.select((state) => state.draft.fields),
    );
    return ConfiguratorCard(
      title: '自定义内容字段',
      trailing: fields.isEmpty ? '未选择' : '已选 ${fields.length} 项',
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: columnSpacing,
          runSpacing: columnSpacing,
          children: <Widget>[
            for (final group in configuratorFieldGroups)
              SizedBox(
                width: _groupWidth(constraints.maxWidth),
                child: _FieldGroup(
                  group: group,
                  selected: fields,
                  onToggle: (field) => ref
                      .read(configuratorProvider.notifier)
                      .toggleField(field),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 一组的宽度：宽屏三列、窄屏两列。
  double _groupWidth(double maxWidth) {
    final columns = maxWidth >= wideBreakpoint ? 3 : 2;
    return (maxWidth - columnSpacing * (columns - 1)) / columns;
  }
}

/// 一组字段。
class _FieldGroup extends StatelessWidget {
  /// 以分组、已选字段与勾选回调构造。
  const new({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  /// 分组定义。
  final ConfiguratorFieldGroup group;

  /// 当前已选的字段。
  final List<String> selected;

  /// 勾选回调。
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          group.label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.tertiaryLabel),
        ),
        const SizedBox(height: groupGap),
        for (final field in group.fields)
          CheckboxListTile(
            value: selected.contains(field),
            onChanged: (_) => onToggle(field),
            // 挤掉的不是「勾不勾」，而是「选了什么」：收起状态时也要看得见。
            title: Text(initializationFieldLabel(field)),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
          ),
      ],
    );
  }
}

/// 三列布局的断点。
const double wideBreakpoint = 720;

/// 列与列之间的间距。
const double columnSpacing = 16;

/// 组名与其下字段的间距。
const double groupGap = 4;
