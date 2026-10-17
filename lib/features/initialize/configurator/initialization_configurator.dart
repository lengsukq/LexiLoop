/// 初始化配置器对话框：外壳与编排。
///
/// 对应旧版 `src/app/(main)/initialize/initialization-configurator.tsx`
/// （447 行、单个组件）。这里只留下骨架与编排：
/// 预设、字段、来源、范围、预览、摘要各自一个文件，
/// 每一块都能单独换掉而不动这个对话框。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_field_picker.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_preset_section.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_preview_card.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_provider_picker.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_scope_section.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_summary_sidebar.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 打开初始化配置器。
///
/// [initialScope] 决定对话框开出来时默认作用在哪些词条上：
/// 从多选浮条进来时必须是 [ConfiguratorScope.selection]，
/// 用户刚勾过的词条不该被「全部词条」顶掉。
Future<void> showInitializationConfigurator(
  BuildContext context, {
  required ConfiguratorScope initialScope,
}) => showDialog<void>(
  context: context,
  builder: (_) => InitializationConfigurator(initialScope: initialScope),
);

/// 初始化配置器对话框。
class InitializationConfigurator extends StatelessWidget {
  /// 以初始范围构造。
  const new({required this.initialScope, super.key});

  /// 打开时的作用范围。
  final ConfiguratorScope initialScope;

  @override
  Widget build(BuildContext context) {
    // 自带一层 ProviderScope：配置器的草稿是**一次性的**，
    // 关掉对话框就该连同预览结果一起丢掉，不能留在全局容器里
    // 等下一次打开时被上一次的字段与范围污染。
    return ProviderScope(
      overrides: [
        configuratorProvider.overrideWith(
          () => ConfiguratorNotifier(initialScope),
        ),
      ],
      child: const _Shell(),
    );
  }
}

/// 对话框骨架：标题、左右两栏、底部动作。
class _Shell extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(dialogInset),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.xl),
          padding: const EdgeInsets.all(dialogPadding),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Header(),
              SizedBox(height: headerGap),
              Flexible(child: _Body()),
              SizedBox(height: headerGap),
              _Actions(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 对话框标题。
class _Header extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '配置初始化',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '先选一个常用方案，需要时再展开下面的细节。',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.tertiaryLabel),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, size: 18),
          tooltip: '关闭',
        ),
      ],
    );
  }
}

/// 左栏（可滚动的主区）与右栏（摘要与预览）。
class _Body extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        // 预设之后的三块默认收起（见 `ConfiguratorDisclosure`）：
        // 打开配置器最常见的动作是「选个方案 → 创建任务」，把 16 个字段
        // 和 6 个数据源全铺在同一屏，只会让这个对话框显得复杂。
        final sections = <Widget>[
          const ConfiguratorPresetSection(),
          const ConfiguratorDetails(),
        ];
        final sidebar = <Widget>[
          const ConfiguratorSummarySidebar(),
          const SizedBox(height: sectionGap),
          const ConfiguratorPreviewCard(),
        ];
        if (!wide) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[...sections, ...sidebar],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sections,
                ),
              ),
            ),
            const SizedBox(width: sectionGap),
            SizedBox(
              width: sidebarWidth,
              child: _SidebarColumn(children: sidebar),
            ),
          ],
        );
      },
    );
  }
}

/// 宽屏下的右栏（自身不滚动，整栏跟随内容高度）。
class _SidebarColumn extends StatelessWidget {
  /// 以各块构造。
  const new({required this.children});

  /// 侧栏的各个块。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

/// 底部动作：提示信息与「创建任务」。
class _Actions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(configuratorProvider);
    final notifier = ref.read(configuratorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.message != null) _Message(state: state),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: state.isBusy
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: inlineGap),
            FilledButton(
              onPressed: state.isBusy
                  ? null
                  : () => unawaited(_create(context, ref, notifier)),
              child: const Text('创建任务'),
            ),
          ],
        ),
      ],
    );
  }

  /// 入队；强制覆盖时先要一次确认。
  ///
  /// 确认放在这里而不是配置器状态里：它是**一次交互**，
  /// 存进状态就等于允许它在对话框重开时被复用。
  Future<void> _create(
    BuildContext context,
    WidgetRef ref,
    ConfiguratorNotifier notifier,
  ) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final destructive =
        ref.read(configuratorProvider).draft.mode ==
        InitializationMode.forceOverwrite;
    final confirmed = !destructive || await confirmOverwrite(context);
    if (!confirmed) return;
    final queued = await notifier.create(overwriteConfirmed: confirmed);
    final message = ref.read(configuratorProvider).message;
    if (!queued) return;
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(message ?? '')));
  }
}

/// 提示信息条。
class _Message extends StatelessWidget {
  /// 以当前状态构造。
  const new({required this.state});

  /// 配置器状态。
  final ConfiguratorState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final color = state.messageIsError ? colors.danger : colors.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: inlineGap),
      child: Text(
        state.message ?? '',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

/// 强制覆盖的二次确认；用户取消时返回 `false`。
Future<bool> confirmOverwrite(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('刷新所选字段？'),
      content: const Text('将只刷新本次选中的字段，其他内容保持不变。确定继续吗？'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('继续'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 对话框离屏幕边缘的内缩。
const double dialogInset = 24;

/// 对话框最大宽度。
const double dialogMaxWidth = 980;

/// 对话框最大高度。
const double dialogMaxHeight = 760;

/// 对话框内边距。
const double dialogPadding = 18;

/// 左右两栏切换成并排的断点。
const double wideBreakpoint = 860;

/// 右栏宽度。
const double sidebarWidth = 300;

/// 三项细节（作用范围 / 字段 / 数据源）的折叠组。
///
/// 默认全部收起；每一项收起时都显示自己的当前值，所以「不展开也知道选了
/// 什么」。首次设置过的用户想改细节，再展开即可。
class ConfiguratorDetails extends ConsumerStatefulWidget {
  /// 以键构造。
  const new({super.key});

  @override
  ConsumerState<ConfiguratorDetails> createState() =>
      _ConfiguratorDetailsState();
}

class _ConfiguratorDetailsState extends ConsumerState<ConfiguratorDetails> {
  bool _scope = false;
  bool _fields = false;
  bool _providers = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(configuratorProvider).draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConfiguratorDisclosure(
          title: '作用范围',
          summary: draft.scope.label,
          expanded: _scope,
          onToggle: () => setState(() => _scope = !_scope),
          child: const ConfiguratorScopeSection(),
        ),
        ConfiguratorDisclosure(
          title: '要补全的字段',
          summary: '${draft.fields.length} 个字段',
          expanded: _fields,
          onToggle: () => setState(() => _fields = !_fields),
          child: const ConfiguratorFieldPicker(),
        ),
        ConfiguratorDisclosure(
          title: '查询来源',
          summary: '${draft.providers.length} 个来源 · 按顺序尝试',
          expanded: _providers,
          onToggle: () => setState(() => _providers = !_providers),
          child: const ConfiguratorProviderPicker(),
        ),
      ],
    );
  }
}
