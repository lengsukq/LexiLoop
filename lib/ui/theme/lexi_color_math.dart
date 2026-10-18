/// 主题色的对比度计算与收敛。
///
/// **为什么需要它**：用户能自由选主色/次色之后，「强调色当文字只有 2:1」
/// 就不再是某一次选色的偶发问题，而是**任意输入**都可能撞上的问题。
/// 这里把「保证可读」做成一个纯函数：给定候选色与一组背景，返回一个
/// 亮度被调整到所有背景上都 ≥4.5:1 的颜色。
///
/// 只做 HSL 亮度调整，不改色相——用户选的颜色仍然是那个颜色，只是
/// 深浅被校准。这是唯一能在「自由选色」与「文字必须可读」之间同时成立的
/// 做法。
library;

import 'package:flutter/material.dart';

/// 主题色计算。
abstract final class LexiColorMath {
  /// 可读性下限（WCAG AA 正文）。
  static const double minContrast = 4.5;

  /// 强调色上文字的候选深色。
  ///
  /// 用近黑而不是纯黑：纯黑压在饱和色上会显得脏，近黑保留一点蓝调。
  static const Color _ink = Color(0xFF0B0F14);

  /// 从色种推导强调色。
  ///
  /// 亮度固定、饱和度夹在 55%–85%：
  /// * 固定亮度让 12 个预设看起来是同一套色板，而不是「有的刺眼有的发灰」；
  /// * 夹住饱和度让灰、白、黑这类极端色种也能得到可用的强调色；
  /// * 色相保留，用户选什么色系就还是什么色系。
  static Color accent(Color seed, {required bool dark}) {
    final hsl = HSLColor.fromColor(seed);
    final hue = hsl.saturation < 0.05 ? _defaultHue : hsl.hue;
    final saturation = hsl.saturation.clamp(0.55, 0.85);
    final lightness = dark ? 0.66 : 0.50;
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }

  /// 强调色的深色变体：浅色模式下压暗一档，深色模式保持不变。
  static Color deepen(Color color, {required bool dark}) {
    if (dark) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0, 1)).toColor();
  }

  /// 把 [color] 调到在全部 [backgrounds] 上都达到 [min] 对比度。
  ///
  /// 背景整体偏亮就压暗，整体偏暗就提亮；逐步移动亮度而不是直接取黑/白，
  /// 是为了尽量保留原来的色相与饱和度。实在到不了下限时退回黑/白里
  /// 对比度更高的那个——那是数学上唯一还能读的选择。
  static Color ensureReadable(
    Color color,
    List<Color> backgrounds, {
    double min = minContrast,
  }) {
    if (backgrounds.isEmpty) return color;
    if (_passes(color, backgrounds, min)) return color;

    final hsl = HSLColor.fromColor(color);
    final averageLuminance =
        backgrounds
            .map((background) => background.computeLuminance())
            .reduce((a, b) => a + b) /
        backgrounds.length;
    final step = averageLuminance > 0.4 ? -0.02 : 0.02;
    var lightness = hsl.lightness;
    for (var i = 0; i < 50; i += 1) {
      lightness = (lightness + step).clamp(0.0, 1.0);
      final candidate = hsl.withLightness(lightness).toColor();
      if (_passes(candidate, backgrounds, min)) return candidate;
      if (lightness == 0 || lightness == 1) break;
    }
    return bestOnAny(backgrounds);
  }

  /// 在 [background] 上选一个对比度最高的前景色。
  static Color bestOn(Color background) => bestOnAny(<Color>[background]);

  /// 在一组背景上选一个「最差情况也最好」的前景色。
  static Color bestOnAny(List<Color> backgrounds) {
    var best = _ink;
    var bestRatio = _worstRatio(_ink, backgrounds);
    // 纯黑是最后兜底：近黑在中等亮度的强调色上可能只有 4.4:1，
    // 而按钮文字必须过 4.5。先保住可读，再谈观感。
    for (final candidate in <Color>[Colors.white, Colors.black]) {
      final ratio = _worstRatio(candidate, backgrounds);
      if (ratio > bestRatio) {
        best = candidate;
        bestRatio = ratio;
      }
    }
    return best;
  }

  /// 两色的对比度（1–21）。
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 一组背景里最低的对比度。
  static double _worstRatio(Color foreground, List<Color> backgrounds) {
    var worst = double.infinity;
    for (final background in backgrounds) {
      final ratio = contrast(foreground, background);
      if (ratio < worst) worst = ratio;
    }
    return worst;
  }

  static bool _passes(Color foreground, List<Color> backgrounds, double min) =>
      _worstRatio(foreground, backgrounds) >= min;

  /// 色种近灰时使用的默认色相（偏薄荷绿）。
  static const double _defaultHue = 158;
}
