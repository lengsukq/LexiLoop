/// 共用的柔和景深与交互节奏。
///
/// **四级影**：静置卡、重点卡、浮动层（导航/浮条）、模态层（弹窗）。
/// 每一级都是「宽而淡的环境影 + 窄而实的接触影」两到三条叠出来的——
/// 单条大模糊会显得脏，单条小阴影又没有体积感。
library;

import 'package:flutter/material.dart';

/// 阴影与交互节奏。
abstract final class LexiDepth {
  /// 静置卡片：几乎看不见，但让白卡从页面底上「浮起来」半毫米。
  static const List<BoxShadow> resting = <BoxShadow>[
    BoxShadow(color: Color(0x0F16233A), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
      color: Color(0x1416233A),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -12,
    ),
  ];

  /// 深色静置卡片：深色下阴影要更实一点才看得出层级。
  static const List<BoxShadow> restingDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x40070C16),
      offset: Offset(0, 10),
      blurRadius: 26,
      spreadRadius: -12,
    ),
  ];

  /// 重点词卡 / 抬升卡。
  static const List<BoxShadow> raised = <BoxShadow>[
    BoxShadow(
      color: Color(0x1416233A),
      offset: Offset(0, 2),
      blurRadius: 6,
      spreadRadius: -1,
    ),
    BoxShadow(
      color: Color(0x2416233A),
      offset: Offset(0, 14),
      blurRadius: 36,
      spreadRadius: -10,
    ),
  ];

  /// 深色抬升卡。
  static const List<BoxShadow> raisedDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x4D070C16),
      offset: Offset(0, 16),
      blurRadius: 40,
      spreadRadius: -12,
    ),
  ];

  /// 浮动层：导航栏、玻璃浮条。
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1416233A),
      offset: Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x3316233A),
      offset: Offset(0, 20),
      blurRadius: 48,
      spreadRadius: -12,
    ),
  ];

  /// 深色浮动层。
  static const List<BoxShadow> floatingDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x66070C16),
      offset: Offset(0, 24),
      blurRadius: 56,
      spreadRadius: -16,
    ),
  ];

  /// 模态层：对话框与底部 Sheet。
  static const List<BoxShadow> modal = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A16233A),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Color(0x4716233A),
      offset: Offset(0, 32),
      blurRadius: 80,
      spreadRadius: -20,
    ),
  ];

  /// 深色模态层。
  static const List<BoxShadow> modalDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x73070C16),
      offset: Offset(0, 32),
      blurRadius: 88,
      spreadRadius: -20,
    ),
  ];

  /// 主按钮的环境影（由主题注入的按钮色染一点主色更好看，但 `ThemeData`
  /// 的 `shadowColor` 只能给单色，因此保留一个中性近黑）。
  static const Color buttonShadow = Color(0x3823483E);

  /// 轻按反馈。
  static const Duration press = Duration(milliseconds: 120);

  /// 内容及选中状态切换。
  static const Duration change = Duration(milliseconds: 220);

  /// 完成反馈。
  static const Duration complete = Duration(milliseconds: 320);

  /// 选出当前明暗模式对应的一组阴影。
  static List<BoxShadow> of(
    List<BoxShadow> light,
    List<BoxShadow> dark, {
    required bool isDark,
  }) => isDark ? dark : light;
}
