/// 共用的柔和景深与交互节奏。
library;

import 'package:flutter/material.dart';

/// 阴影只用于重点表面和浮层，普通内容保持平整。
abstract final class LexiDepth {
  /// 重点词卡的宽柔影与接触影。
  static const List<BoxShadow> raised = <BoxShadow>[
    BoxShadow(
      color: Color(0x192D456F),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x0D2D456F),
      offset: Offset(0, 2),
      blurRadius: 6,
      spreadRadius: -1,
    ),
  ];

  /// 深色下避免灰黑色脏边。
  static const List<BoxShadow> raisedDark = <BoxShadow>[
    BoxShadow(
      color: Color(0x38080E1B),
      offset: Offset(0, 10),
      blurRadius: 28,
      spreadRadius: -6,
    ),
  ];

  /// 主按钮的环境影。
  static const Color buttonShadow = Color(0x3823483E);

  /// 轻按反馈。
  static const Duration press = Duration(milliseconds: 120);

  /// 内容及选中状态切换。
  static const Duration change = Duration(milliseconds: 180);

  /// 完成反馈。
  static const Duration complete = Duration(milliseconds: 300);
}
