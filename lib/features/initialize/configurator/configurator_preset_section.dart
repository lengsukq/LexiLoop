/// 预设选择区（配置的起点）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_fields.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_providers.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 四个初始化预设。
///
/// **为什么放在最上面**：可选字段有 16 个、数据源有 5 个，
/// 先让用户点一次「基础词典信息」，再在下面微调，
/// 比从空白开始勾要快一个量级。
class ConfiguratorPresetSection extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(configuratorProvider.select((s) => s.draft));
    final active = activeConfiguratorPreset(
      draft.fields,
      youdaoOnly: draft.youdaoOnly,
    );
    return ConfiguratorCard(
      title: '选择内容补全方案',
      // 选中预设时**不再重复它的名字**：卡片本身已经高亮并写着它。
      // 只有「自定义」这种卡片表达不了的状态才需要这一行。
      trailing: active == null ? '自定义 ${draft.fields.length} 项' : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // **按可用宽度算列数**。写死 `Wrap` + 固定宽时，4 张卡在左栏
          // 只放得下 3 张，第 4 张单独换行、右边空出三分之二——看起来像
          // 布局坏了。2×2 或 1×4 都是整齐的，3+1 不是。
          final columns =
              constraints.maxWidth >= presetTileWidth * 4 + inlineGap * 3
              ? 4
              : (constraints.maxWidth >= tileWidth * 2 + inlineGap ? 2 : 1);
          final width =
              (constraints.maxWidth - inlineGap * (columns - 1)) / columns;
          return Wrap(
            spacing: inlineGap,
            runSpacing: inlineGap,
            children: <Widget>[
              for (final preset in configuratorPresets)
                SizedBox(
                  width: width,
                  child: ConfiguratorPresetTile(
                    preset: preset,
                    selected: active?.label == preset.label,
                    onTap: () => ref
                        .read(configuratorProvider.notifier)
                        .applyPreset(preset),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 单个预设卡片。
class ConfiguratorPresetTile extends ConsumerWidget {
  /// 以预设、选中态与点击回调构造。
  const new({
    required this.preset,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// 预设定义。
  final ConfiguratorPreset preset;

  /// 是否为当前生效的预设。
  final bool selected;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = _blockedReason(ref);
    return SizedBox(
      width: double.infinity,
      child: _TileBody(
        preset: preset,
        selected: selected,
        enabled: blocked == null,
        description: blocked ?? preset.description,
        onTap: blocked == null ? onTap : null,
      ),
    );
  }

  /// 预设当前不可用的原因。
  ///
  /// 只有「仅有道词典」会不可用：有道被关掉时，这个预设选出来的来源
  /// 会被 [ConfiguratorNotifier._invalidReason] 判成「没选来源」，
  /// 与其让用户点完才发现，不如在卡片上就说明。
  String? _blockedReason(WidgetRef ref) {
    if (!preset.youdaoOnly) return null;
    final options = ref.watch(configuratorProviderOptionsProvider).asData;
    if (options == null) return '正在检查有道词典状态';
    final youdao = configuratorProviderOption(options.value, youdaoProviderId);
    if (youdao == null) return '当前版本未提供有道词典';
    return youdao.available ? null : (youdao.reason ?? '有道词典当前不可用');
  }
}

/// 预设卡片的内容（图标、名称、说明）。
class _TileBody extends StatelessWidget {
  /// 以预设与展示状态构造。
  const new({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.description,
    required this.onTap,
  });

  /// 预设定义。
  final ConfiguratorPreset preset;

  /// 是否选中。
  final bool selected;

  /// 是否可点。
  final bool enabled;

  /// 说明文案（不可用时展示原因）。
  final String description;

  /// 点击回调；不可用时为 `null`。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = !enabled
        ? colors.quaternaryLabel
        : selected
        ? colors.accent
        : colors.secondaryLabel;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(tilePadding),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: LexiTint.tint)
              : colors.fill,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(preset.icon, size: iconSize, color: foreground),
            const SizedBox(height: tileGap),
            Text(
              preset.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: enabled ? colors.label : colors.tertiaryLabel,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LexiSpace.s2),
            Text(
              description,
              maxLines: descriptionMaxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.tertiaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预设卡片宽度。
const double tileWidth = 156;

/// 一行放下四张预设所需的最小宽度。
const double presetTileWidth = 172;

/// 预设卡片内边距。
const double tilePadding = 12;

/// 预设卡片内的纵向间距。
const double tileGap = 6;

/// 预设图标尺寸。
const double iconSize = 18;

/// 说明文案最多展示的行数。
const int descriptionMaxLines = 2;
