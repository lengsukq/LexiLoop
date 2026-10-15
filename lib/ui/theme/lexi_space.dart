/// LexiLoop 的间距音阶（4pt 网格）。
///
/// **为什么需要它**：收敛前 `SizedBox` 与 `EdgeInsets` 里出现过 19 种间距值，
/// 其中 3 / 5 / 7 / 9 / 14 / 18 落在 4pt 网格之外。网格外的一两个像素在单屏
/// 上看不出来，但同一列卡片之间「有的差 12、有的差 14」会让人说不出哪里别扭。
///
/// 档位是 4 的倍数，外加 `s2` 与 `s6` 两个半档：`s2` 用于图标与文字的紧贴
/// （2pt 无法用 4 表达），`s6` 用于「比 4 松、比 8 紧」的行内间隔。
/// 其余一律用 4 的倍数。
library;

/// 间距音阶：从 2 到 40。
abstract final class LexiSpace {
  /// 2 磅：图标与紧邻文字之间的光学间距。
  static const double s2 = 2;

  /// 4 磅：最小间隔。
  static const double s4 = 4;

  /// 6 磅：行内元素之间的间隔。
  static const double s6 = 6;

  /// 8 磅：同一组元素之间的间隔。
  static const double s8 = 8;

  /// 12 磅：组与组之间的间隔。
  static const double s12 = 12;

  /// 16 磅：区块内边距。
  static const double s16 = 16;

  /// 20 磅：区块之间的间隔。
  static const double s20 = 20;

  /// 24 磅：页面级留白。
  static const double s24 = 24;

  /// 32 磅：大留白。
  static const double s32 = 32;

  /// 40 磅：页面顶部/底部的呼吸空间。
  static const double s40 = 40;

  /// 全部档位，供守卫测试断言「都落在 4pt 网格上（2 与 6 为声明的半档）」。
  static const List<double> steps = <double>[
    s2,
    s4,
    s6,
    s8,
    s12,
    s16,
    s20,
    s24,
    s32,
    s40,
  ];
}
