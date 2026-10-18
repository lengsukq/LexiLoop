/// 内容分区的柔和彩色表面；与成功、错误等状态色分开。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 固定角色的分区配色，明暗模式共用同一角色。
enum LexiTone {
  /// 主要学习内容与完成进度。
  mint(
    Color(0xFFE0F5EA),
    Color(0xFF21362E),
    Color(0xFF146C4B),
    Color(0xFF86DAB5),
  ),

  /// 资料、词典与统计。
  sky(
    Color(0xFFE5F1FF),
    Color(0xFF233446),
    Color(0xFF2B629C),
    Color(0xFF99C7FB),
  ),

  /// 专项练习与配置。
  lavender(
    Color(0xFFF0EAFE),
    Color(0xFF342D46),
    Color(0xFF704DA3),
    Color(0xFFC8B0F1),
  ),

  /// 学习建议与辅助提醒。
  peach(
    Color(0xFFFFF0DF),
    Color(0xFF3B3027),
    Color(0xFF95531B),
    Color(0xFFEDC395),
  );

  new(this._light, this._dark, this._lightInk, this._darkInk);

  final Color _light;
  final Color _dark;
  final Color _lightInk;
  final Color _darkInk;

  /// 不透明分区底色。
  Color background(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// 标题图标及强调文字。
  Color foreground(Brightness brightness) =>
      brightness == Brightness.dark ? _darkInk : _lightInk;

  /// 与底色同色系的细边框。
  Color border(Brightness brightness) => Color.alphaBlend(
    foreground(brightness).withValues(alpha: LexiTint.tint),
    background(brightness),
  );
}
