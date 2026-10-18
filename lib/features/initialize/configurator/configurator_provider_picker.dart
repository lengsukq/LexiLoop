/// 数据源选择与调用策略。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_providers.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/services/dictionary/selection.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 数据源列表（可用性 + 优先级排序）与调用策略。
///
/// 列表顺序固定为执行顺序，勾选框决定「参不参与」，
/// 上下箭头决定「谁先调用」——把这两件事拆成两个控件之后，
/// 「为什么有道没被调」和「为什么先调了爱词霸」不再混成一个问题。
class ConfiguratorProviderPicker extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(configuratorProvider.select((s) => s.draft));
    final options = ref.watch(configuratorProviderOptionsProvider);
    final notifier = ref.read(configuratorProvider.notifier);
    return ConfiguratorCard(
      title: '数据来源与执行策略',
      trailing: draft.providers.isEmpty
          ? '尚未选择来源'
          : '${draft.providers.length} 个来源',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (draft.youdaoOnly)
            _LockedNotice(onUnlock: notifier.unlockSources)
          else
            _ProviderList(
              state: options,
              draft: draft,
              onToggle: notifier.toggleProvider,
              onMove: notifier.moveProvider,
            ),
          if (!draft.youdaoOnly) ...<Widget>[
            const SizedBox(height: sectionGap),
            _StrategyChoice(
              strategy: draft.strategy,
              onChanged: notifier.setStrategy,
            ),
          ],
        ],
      ),
    );
  }
}

/// 来源列表（加载中 / 失败 / 正常三态）。
class _ProviderList extends ConsumerWidget {
  /// 以选项加载态、草稿与两个回调构造。
  const new({
    required this.state,
    required this.draft,
    required this.onToggle,
    required this.onMove,
  });

  /// 来源选项的加载态。
  final AsyncValue<List<ConfiguratorProviderOption>> state;

  /// 当前草稿。
  final ConfiguratorDraft draft;

  /// 勾选回调。
  final void Function(String id) onToggle;

  /// 上移 / 下移回调。
  final void Function(String id, int offset) onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text(
        '加载来源状态失败：$error',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: context.lexiColors.dangerText),
      ),
      data: (options) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final option in options)
            ProviderRow(
              input: ProviderRowInput(
                option: option,
                fields: draft.fields,
                index: draft.providers.indexOf(option.id),
                total: draft.providers.length,
              ),
              onToggle: () => onToggle(option.id),
              onMove: (offset) => onMove(option.id, offset),
            ),
        ],
      ),
    );
  }
}

/// 一行数据源的展示参数。
///
/// 单独成类是为了守住「构造函数不超过 5 个参数」这条约束——
/// 选项、字段、序号、总数再加两个回调会超标。
class ProviderRowInput {
  /// 以来源、当前字段、优先级位置与优先级总数构造。
  const new({
    required this.option,
    required this.fields,
    required this.index,
    required this.total,
  });

  /// 来源选项。
  final ConfiguratorProviderOption option;

  /// 当前勾选的内容字段。
  final List<String> fields;

  /// 在优先级列表中的下标；`−1` 表示未勾选。
  final int index;

  /// 优先级列表长度。
  final int total;

  /// 是否已勾选。
  bool get selected => index >= 0;

  /// 能力是否与当前勾选的字段有交集。
  bool get compatible => providerSupportsFields(option, fields);

  /// 是否可勾选。
  bool get selectable => option.available && compatible;
}

/// 单个数据源行。
///
/// **不可用的来源仍然列出来**：用户真正要的是「为什么它没被选中」，
/// 把它藏起来只会让人跑去设置页里瞎猜。
class ProviderRow extends StatelessWidget {
  /// 以展示参数与两个回调构造。
  const new({
    required this.input,
    required this.onToggle,
    required this.onMove,
    super.key,
  });

  /// 展示参数。
  final ProviderRowInput input;

  /// 勾选回调。
  final VoidCallback onToggle;

  /// 上移 / 下移回调。
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final selected = input.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: rowSpacing),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: selected,
            onChanged: input.selectable ? (_) => onToggle() : null,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  input.option.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: LexiSpace.s2),
                Text(
                  _reason,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: input.selectable
                        ? colors.tertiaryLabel
                        : colors.warning,
                  ),
                ),
              ],
            ),
          ),
          if (selected) ...<Widget>[
            _PriorityBadge(index: input.index + 1),
            _MoveButton(
              icon: LucideIcons.chevronUp,
              tooltip: '提高优先级',
              onPressed: input.index == 0 ? null : () => onMove(-1),
            ),
            _MoveButton(
              icon: LucideIcons.chevronDown,
              tooltip: '降低优先级',
              onPressed: input.index == input.total - 1
                  ? null
                  : () => onMove(1),
            ),
          ],
        ],
      ),
    );
  }

  /// 不可用时展示原因，可用时展示能力说明。
  String get _reason {
    final option = input.option;
    if (!option.available) return option.reason ?? '当前不可用';
    if (!input.compatible) return providerFieldMismatchReason;
    return option.description;
  }
}

/// 优先级序号徽标。
class _PriorityBadge extends StatelessWidget {
  /// 以序号构造。
  const new({required this.index});

  /// 从 1 开始的优先级序号。
  final int index;

  @override
  Widget build(BuildContext context) =>
      LexiBadge(label: '$index', tone: LexiBadgeTone.accent);
}

/// 上移 / 下移按钮。
class _MoveButton extends StatelessWidget {
  /// 以图标、提示与回调构造。
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// 图标。
  final IconData icon;

  /// 无障碍提示。
  final String tooltip;

  /// 点击回调；到头时为 `null`。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    icon: Icon(icon, size: moveIconSize),
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
  );
}

/// 「已锁定为有道词典」提示与解锁入口。
class _LockedNotice extends StatelessWidget {
  /// 以解锁回调构造。
  const new({required this.onUnlock});

  /// 解锁回调。
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '已锁定为有道词典',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: colors.label),
        ),
        const SizedBox(height: LexiSpace.s2),
        Text(
          '本次任务只会请求有道词典，不会调用其他词典、翻译服务或 AI。',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: inlineGap),
        TextButton(onPressed: onUnlock, child: const Text('切换为自定义来源')),
      ],
    );
  }
}

/// 调用策略单选。
class _StrategyChoice extends StatelessWidget {
  /// 以当前策略与回调构造。
  const new({required this.strategy, required this.onChanged});

  /// 当前策略。
  final ProviderStrategy strategy;

  /// 切换回调。
  final ValueChanged<ProviderStrategy> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: inlineGap,
    runSpacing: inlineGap,
    children: <Widget>[
      for (final option in _strategyOptions)
        StrategyCard(
          label: option.label,
          description: option.description,
          selected: option.value == strategy,
          onTap: () => onChanged(option.value),
        ),
    ],
  );
}

/// 一种调用策略的展示信息。
class _StrategyOption {
  /// 以取值、名称与说明构造。
  const new(this.value, this.label, this.description);

  /// 策略取值。
  final ProviderStrategy value;

  /// 名称。
  final String label;

  /// 一句话说明。
  final String description;
}

/// 可选的两种策略。
const List<_StrategyOption> _strategyOptions = <_StrategyOption>[
  _StrategyOption(
    ProviderStrategy.priorityFallback,
    '按优先级回退',
    '满足字段后停止请求后续来源，省流量',
  ),
  _StrategyOption(ProviderStrategy.parallelMerge, '全部查询并合并', '适合例句、近义词等汇总内容'),
];

/// 单个策略卡片。
class StrategyCard extends StatelessWidget {
  /// 以名称、说明、选中态与点击回调构造。
  const new({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// 名称。
  final String label;

  /// 一句话说明。
  final String description;

  /// 是否选中。
  final bool selected;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: Container(
        width: strategyCardWidth,
        padding: const EdgeInsets.all(inlineGap),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: LexiTint.tint)
              : colors.fill,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: strategyIconSize,
              color: selected ? colors.accent : colors.tertiaryLabel,
            ),
            const SizedBox(width: inlineGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.tertiaryLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 策略卡片宽度。
const double strategyCardWidth = 220;

/// 策略卡片的单选图标尺寸。
const double strategyIconSize = 16;

/// 来源行之间的间距。
const double rowSpacing = 4;

/// 序号徽标的水平内边距。
const double badgePaddingH = 7;

/// 上移 / 下移图标的尺寸。
const double moveIconSize = 20;
