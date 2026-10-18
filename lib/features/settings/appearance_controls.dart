/// 外观设置用到的控件：模式选择、色板、自定义色种与实时预览。
///
/// 单独成文件的原因：设置页已经有 8 个分组，把取色器塞进分组会同时撑大
/// 两个 `build()`。这里只依赖 token 与 `LexiBadge`，不碰数据库。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/ui/theme/lexi_color_math.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_palette.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 外观模式的三个选项。
class AppearanceModePicker extends StatelessWidget {
  /// 以当前模式与回调构造。
  const new({required this.mode, required this.onChanged, super.key});

  /// 当前模式。
  final AppThemeMode mode;

  /// 选择回调。
  final ValueChanged<AppThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AppThemeMode>(
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      segments: const <ButtonSegment<AppThemeMode>>[
        ButtonSegment<AppThemeMode>(
          value: AppThemeMode.system,
          label: Text('跟随系统', key: Key('appearanceModeSystem')),
        ),
        ButtonSegment<AppThemeMode>(
          value: AppThemeMode.light,
          label: Text('浅色', key: Key('appearanceModeLight')),
        ),
        ButtonSegment<AppThemeMode>(
          value: AppThemeMode.dark,
          label: Text('深色', key: Key('appearanceModeDark')),
        ),
      ],
      selected: <AppThemeMode>{mode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// 一组圆形色板 + 「自定义」入口。
class ColorSeedPicker extends StatelessWidget {
  /// 以选择结果、当前值与回调构造。
  const new({
    required this.role,
    required this.selected,
    required this.onSelected,
    required this.onCustom,
    super.key,
  });

  /// `primary` 或 `secondary`，用于生成稳定的测试 Key。
  final String role;

  /// 当前色种。
  final Color selected;

  /// 选中预设。
  final ValueChanged<Color> onSelected;

  /// 打开自定义取色。
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LexiSpace.s10,
      runSpacing: LexiSpace.s10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final preset in LexiPalette.presets)
          _ColorDot(
            key: Key('appearance${_titleCase(role)}Swatch-${preset.id}'),
            preset: preset,
            selected: selected.toARGB32() == preset.argb,
            onTap: () => onSelected(preset.color),
          ),
        TextButton.icon(
          key: Key('appearance${_titleCase(role)}Custom'),
          onPressed: onCustom,
          icon: const Icon(Icons.palette_outlined, size: 18),
          label: const Text('自定义…'),
        ),
      ],
    );
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}

class _ColorDot extends StatelessWidget {
  const new({
    required this.preset,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final LexiColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Semantics(
      label: '${preset.label}${selected ? '，已选中' : ''}',
      button: true,
      child: Tooltip(
        message: preset.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: preset.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.card : Colors.transparent,
                width: 3,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: preset.color.withValues(alpha: selected ? 0.4 : 0.2),
                  blurRadius: selected ? 10 : 4,
                  offset: const Offset(0, 2),
                ),
                if (selected)
                  BoxShadow(
                    color: colors.accent.withValues(alpha: LexiTint.half),
                    spreadRadius: 2,
                  ),
              ],
            ),
            child: selected
                ? Icon(Icons.check, size: 16, color: colors.onAccent)
                : null,
          ),
        ),
      ),
    );
  }
}

/// 当前外观的迷你预览：主/次色如何落到按钮、进度与文字上。
class AppearancePreview extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      key: const Key('appearancePreview'),
      variant: SurfaceVariant.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '主题预览',
                  style: LexiType.title.copyWith(color: colors.label),
                ),
              ),
              const LexiBadge(label: '主色', tone: LexiBadgeTone.accent),
            ],
          ),
          const SizedBox(height: LexiSpace.s4),
          Text(
            '这是一段正文，四级文字层级都会跟着明暗模式保持可读。',
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s14),
          ClipRRect(
            borderRadius: BorderRadius.circular(LexiRadius.pill),
            child: LinearProgressIndicator(
              value: 0.62,
              minHeight: 8,
              backgroundColor: colors.fill,
            ),
          ),
          const SizedBox(height: LexiSpace.s14),
          Wrap(
            spacing: LexiSpace.s10,
            runSpacing: LexiSpace.s10,
            children: <Widget>[
              FilledButton(onPressed: () {}, child: const Text('主按钮')),
              OutlinedButton(onPressed: () {}, child: const Text('次按钮')),
              TextButton(onPressed: () {}, child: const Text('文字按钮')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 自定义色种对话框：只调色相与饱和度，亮度交给主题引擎。
Future<Color?> showColorSeedDialog(
  BuildContext context, {
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) => _ColorSeedDialog(initial: initial),
  );
}

class _ColorSeedDialog extends StatefulWidget {
  const new({required this.initial});

  final Color initial;

  @override
  State<_ColorSeedDialog> createState() => _ColorSeedDialogState();
}

class _ColorSeedDialogState extends State<_ColorSeedDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final preview = LexiColorMath.accent(
      _hsv.toColor(),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return AlertDialog(
      title: const Text('自定义色种'),
      content: SizedBox(
        width: _dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: _previewSize,
                height: _previewSize,
                decoration: BoxDecoration(
                  color: preview,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: preview.withValues(alpha: LexiTint.border),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LexiSpace.s16),
            const Text('色相', style: LexiType.footnote),
            Slider(
              value: _hsv.hue,
              max: 360,
              divisions: 360,
              activeColor: preview,
              onChanged: (value) => setState(() => _hsv = _hsv.withHue(value)),
            ),
            const Text('饱和度', style: LexiType.footnote),
            Slider(
              value: _hsv.saturation.clamp(_minSaturation, _maxSaturation),
              min: _minSaturation,
              max: _maxSaturation,
              divisions: 55,
              activeColor: preview,
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withSaturation(value)),
            ),
            Text(
              '亮度会自动校准，保证文字在明暗两种模式下都可读。',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('appearanceCustomConfirm'),
          onPressed: () => Navigator.of(context).pop(_hsv.toColor()),
          child: const Text('使用这个颜色'),
        ),
      ],
    );
  }
}

const double _dotSize = 32;
const double _previewSize = 56;
const double _dialogWidth = 320;
const double _minSaturation = 0.35;
const double _maxSaturation = 0.9;
