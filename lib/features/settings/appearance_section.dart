/// 设置 › 外观。
///
/// 三项设置（模式 / 主色 / 次色）都即时写库：本应用没有「保存」语义，
/// 改完切走再回来看到的就是生效值。写失败由 [saveSettings] 统一回滚并提示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/features/settings/appearance_controls.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/settings_providers.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';

/// 外观设置分组。
class AppearanceSection extends ConsumerWidget {
  /// 以当前设置构造。
  const new({required this.settings, super.key});

  /// 当前应用设置。
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = settings.appearance;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        SettingsSectionCard(
          title: '外观模式',
          subtitle: '跟随系统会在白天与夜间自动切换。',
          child: AppearanceModePicker(
            mode: appearance.mode,
            onChanged: (mode) =>
                _save(ref, <String, Object?>{'themeMode': mode.wire}),
          ),
        ),
        SettingsSectionCard(
          title: '主色',
          subtitle: '按钮、进度、选中态与焦点使用主色；亮度会自动校准以保证可读。',
          child: ColorSeedPicker(
            role: 'primary',
            selected: Color(appearance.primaryColor),
            onSelected: (color) => _save(ref, <String, Object?>{
              'themePrimaryColor': color.toARGB32(),
            }),
            onCustom: () => _pickCustom(
              context,
              ref,
              initial: Color(appearance.primaryColor),
              key: 'themePrimaryColor',
            ),
          ),
        ),
        SettingsSectionCard(
          title: '次色',
          subtitle: '次级动作、双色渐变与图表第二序列使用次色。',
          child: ColorSeedPicker(
            role: 'secondary',
            selected: Color(appearance.secondaryColor),
            onSelected: (color) => _save(ref, <String, Object?>{
              'themeSecondaryColor': color.toARGB32(),
            }),
            onCustom: () => _pickCustom(
              context,
              ref,
              initial: Color(appearance.secondaryColor),
              key: 'themeSecondaryColor',
            ),
          ),
        ),
        const SettingsSectionCard(
          title: '预览',
          subtitle: '预览使用当前外观重新绘制，不需要先保存。',
          child: AppearancePreview(),
        ),
        const SizedBox(height: LexiSpace.s8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('appearanceReset'),
            onPressed: () => _save(ref, <String, Object?>{
              'themeMode': null,
              'themePrimaryColor': null,
              'themeSecondaryColor': null,
            }),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('恢复默认外观'),
          ),
        ),
        const SizedBox(height: LexiSpace.s24),
        const _AboutColors(),
      ],
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    WidgetRef ref, {
    required Color initial,
    required String key,
  }) async {
    final picked = await showColorSeedDialog(context, initial: initial);
    if (picked == null) return;
    await _save(ref, <String, Object?>{key: picked.toARGB32()});
  }

  Future<void> _save(WidgetRef ref, Map<String, Object?> changes) =>
      saveSettings(ref, changes);
}

/// 「关于配色」折叠说明。
class _AboutColors extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => DisclosureSection(
    title: '关于配色',
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: LexiLayout.readingMaxWidth),
      child: const Text(
        '主色与次色是「色种」：应用会按当前明暗模式重新计算亮度， '
        '确保正文文字与彩色按钮上的文字都达到 4.5:1 的对比度。 '
        '危险、成功、警告与关联词仍使用固定语义色，不会随主题改变。',
        style: LexiType.footnote,
      ),
    ),
  );
}
