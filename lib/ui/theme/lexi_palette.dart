/// 可作为主色/次色的预设色种。
///
/// 色值取自 iOS 系统色板。它们是**色种**而不是最终强调色：最终颜色由
/// `LexiColors.resolve` 按明暗模式重新计算亮度，保证文字可读。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';

/// 一个可选色种。
@immutable
class LexiColorPreset {
  /// 以稳定标识、中文名与色种构造。
  const new({required this.id, required this.label, required this.color});

  /// 稳定标识（存储/测试用，不随文案变化）。
  final String id;

  /// 界面文案。
  final String label;

  /// 色种（不透明）。
  final Color color;

  /// 存储用的 ARGB 整数。
  int get argb => color.toARGB32();
}

/// 全部预设，按界面展示顺序排列。
abstract final class LexiPalette {
  /// 主色/次色共用的 12 个预设。
  static const List<LexiColorPreset> presets = <LexiColorPreset>[
    LexiColorPreset(
      id: 'mint',
      label: '薄荷',
      color: Color(defaultThemePrimaryColor),
    ),
    LexiColorPreset(id: 'blue', label: '海蓝', color: Color(0xFF0A84FF)),
    LexiColorPreset(id: 'teal', label: '青', color: Color(0xFF30B0C7)),
    LexiColorPreset(id: 'green', label: '草绿', color: Color(0xFF34C759)),
    LexiColorPreset(
      id: 'indigo',
      label: '靛蓝',
      color: Color(defaultThemeSecondaryColor),
    ),
    LexiColorPreset(id: 'purple', label: '紫', color: Color(0xFFAF52DE)),
    LexiColorPreset(id: 'pink', label: '粉', color: Color(0xFFFF2D55)),
    LexiColorPreset(id: 'red', label: '红', color: Color(0xFFFF3B30)),
    LexiColorPreset(id: 'orange', label: '橙', color: Color(0xFFFF9500)),
    LexiColorPreset(id: 'yellow', label: '黄', color: Color(0xFFFFCC00)),
    LexiColorPreset(id: 'brown', label: '棕', color: Color(0xFFA2845E)),
    LexiColorPreset(id: 'graphite', label: '石墨', color: Color(0xFF8E8E93)),
  ];

  /// 默认主色对应的预设。
  static const LexiColorPreset defaultPrimary = LexiColorPreset(
    id: 'mint',
    label: '薄荷',
    color: Color(defaultThemePrimaryColor),
  );

  /// 默认次色对应的预设。
  static const LexiColorPreset defaultSecondary = LexiColorPreset(
    id: 'indigo',
    label: '靛蓝',
    color: Color(defaultThemeSecondaryColor),
  );

  /// 按色值找最接近的预设；没有完全相等时返回 `null`（说明是自定义色）。
  static LexiColorPreset? match(Color color) {
    for (final preset in presets) {
      if (preset.color.toARGB32() == color.toARGB32()) return preset;
    }
    return null;
  }

  /// 按 id 取预设；未知 id 返回 `null`。
  static LexiColorPreset? byId(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
