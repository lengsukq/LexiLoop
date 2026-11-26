/// LexiLoop 的间距音阶（2pt 节奏）。
///
/// **为什么需要它**：收敛前 `SizedBox` 与 `EdgeInsets` 里出现过 25 种间距值，
/// 其中 1 / 2.5 / 3 / 5 / 7 / 9 / 18 / 22 / 28 / 48 落在 2pt 节奏之外。差一
/// 两个像素在单屏上看不出来，但同一列卡片之间「有的差 12、有的差 14」会让
/// 人说不出哪里别扭。
///
/// 档位取 2pt 节奏上**真正被反复使用**的那些值。10 与 14 各自被用了近百次，
/// 属于实际的主力档位，因此收编为 `s10` / `s14`，而不是把它们硬掰到 8 或 12；
/// 反过来 18 只有 8 处、明显是漂移，就并到 `s20`。
///
/// 间距之外的**尺寸**（列宽、头像边长、点击热区）不属于这套音阶，应当就地
/// 命名成有语义的 `const`，而不是塞进这里。
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

  /// 10 磅：紧凑控件的内边距。
  static const double s10 = 10;

  /// 12 磅：组与组之间的间隔。
  static const double s12 = 12;

  /// 14 磅：列表行、内嵌块的内边距。
  static const double s14 = 14;

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

  /// 全部档位，供守卫测试断言「都落在 2pt 节奏上」。
  static const List<double> steps = <double>[
    s2,
    s4,
    s6,
    s8,
    s10,
    s12,
    s14,
    s16,
    s20,
    s24,
    s32,
    s40,
  ];
}
