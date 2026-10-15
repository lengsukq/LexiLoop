/// 作用范围与写入方式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 词条范围与写入方式。
///
/// 两个分段选择器并排：它们回答的都是「对谁做什么」，
/// 放在一处比拆成两段更省一次来回扫视。
class ConfiguratorScopeSection extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(configuratorProvider.select((s) => s.draft));
    final selected = ref.watch(queueSelectionProvider).length;
    final notifier = ref.read(configuratorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ScopeBar(
          draft: draft,
          selectedCount: selected,
          onChanged: notifier.setScope,
        ),
        const SizedBox(height: sectionGap),
        _ModeBar(mode: draft.mode, onChanged: notifier.setMode),
        if (draft.mode == InitializationMode.forceOverwrite) ...<Widget>[
          const SizedBox(height: inlineGap),
          Text(
            '刷新所选字段会覆盖词典抓来的内容（你手工编辑的释义与例句会保留），'
            '创建前还会再确认一次。',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.lexiColors.warning),
          ),
        ],
      ],
    );
  }
}

/// 词条范围分段。
class _ScopeBar extends StatelessWidget {
  /// 以草稿、已选数量与回调构造。
  const new({
    required this.draft,
    required this.selectedCount,
    required this.onChanged,
  });

  /// 当前草稿。
  final ConfiguratorDraft draft;

  /// 队列列表里已勾选的词条数。
  final int selectedCount;

  /// 切换回调。
  final ValueChanged<ConfiguratorScope> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const ConfiguratorSectionHeader(title: '词条范围'),
      const SizedBox(height: headerGap),
      ConfiguratorSegmentBar(
        children: <Widget>[
          for (final scope in ConfiguratorScope.values)
            ConfiguratorSegment(
              label: _label(scope, selectedCount),
              selected: draft.scope == scope,
              onTap: () => onChanged(scope),
            ),
        ],
      ),
    ],
  );

  /// 「已选词条」带上当前勾选数，避免用户以为这一档是空的。
  String _label(ConfiguratorScope scope, int count) =>
      scope == ConfiguratorScope.selection && count > 0
      ? '${scope.label}（$count）'
      : scope.label;
}

/// 写入方式分段。
class _ModeBar extends StatelessWidget {
  /// 以当前写入方式与回调构造。
  const new({required this.mode, required this.onChanged});

  /// 当前写入方式。
  final InitializationMode mode;

  /// 切换回调。
  final ValueChanged<InitializationMode> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const ConfiguratorSectionHeader(title: '写入方式'),
      const SizedBox(height: headerGap),
      ConfiguratorSegmentBar(
        children: <Widget>[
          for (final option in _modeOptions)
            ConfiguratorSegment(
              label: option.label,
              selected: option.mode == mode,
              onTap: () => onChanged(option.mode),
            ),
        ],
      ),
    ],
  );
}

/// 一种写入方式的展示信息。
class _ModeOption {
  /// 以取值与名称构造。
  const new(this.mode, this.label);

  /// 写入方式。
  final InitializationMode mode;

  /// 名称。
  final String label;
}

/// 可选的两种写入方式。
const List<_ModeOption> _modeOptions = <_ModeOption>[
  _ModeOption(InitializationMode.fillMissingFields, '仅补缺失'),
  _ModeOption(InitializationMode.forceOverwrite, '刷新所选'),
];
