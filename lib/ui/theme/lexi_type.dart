/// LexiLoop 的排版音阶。
///
/// **为什么必须有音阶**：收敛前全应用出现过 25 种字号，其中 6 种是半点值
/// （10.5 / 11.5 / 12.5 / 13.5 / 14.5 / 15.5），合计 163 处。半点值不是设计
/// 决定，是「这次想大一点点」的临时产物——它们让同一层级的文字在不同页面
/// 差半磅，是界面看起来不统一最直接的原因。
///
/// **档位取自 macOS 原生音阶**（`docs/...` 与 Apple HIG `typography.md` 的
/// 「macOS built-in text styles」一致：11 / 12 / 13 / 15 / 17 / 22 / 26）。
/// 这里在其上补了 `display 30` 与 `hero 34` 两档给「词条主视觉」与「大数字」。
///
/// **行高**：Apple 给每一档都配了行高（body 13/16、title 17/22 …）。Flutter 的
/// `height` 是倍数而不是磅值，所以这里写成 `行高 / 字号` 的除法，读起来仍是
/// 「13 磅字、18 磅行」。
///
/// **这些 token 不带颜色**：颜色是语义（`LexiColors`），字号是排版，两者正交。
/// 需要特定颜色时用 `LexiType.body.copyWith(color: colors.secondaryLabel)`。
/// 守卫测试禁止 `lib/` 里出现 `fontSize:` 字面量，所以字号只能从这里取。
library;

import 'package:flutter/material.dart';

/// 排版音阶：9 档，每档固定字号、行高与字重。
///
/// 字重只承担「强调」一层含义，不参与层级划分——层级由档位决定。
abstract final class LexiType {
  /// 紧凑信息与徽章。
  static const TextStyle caption = TextStyle(fontSize: 12, height: 16 / 12);

  /// 字段说明与音标。
  static const TextStyle footnote = TextStyle(fontSize: 13, height: 18 / 13);

  /// 桌面正文；手机提升到 16。
  static const TextStyle body = TextStyle(fontSize: 14, height: 20 / 14);

  /// 操作标签。
  static const TextStyle callout = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w500,
  );

  /// 内容分区标题。
  static const TextStyle title = TextStyle(
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );

  /// 主要分区。
  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
  );

  /// 页面标题。
  static const TextStyle page = TextStyle(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// 学习词条。
  static const TextStyle display = TextStyle(
    fontSize: 36,
    height: 44 / 36,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.7,
  );

  /// 任务数字与成果。
  static const TextStyle hero = TextStyle(
    fontSize: 40,
    height: 46 / 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
  );

  /// 全部档位，按字号升序。
  ///
  /// 供守卫测试断言「严格递增」与「最小值不低于 11」——音阶一旦被插入一个
  /// 中间值，层级就又回到了「想大一点点」的老路。
  static const List<TextStyle> steps = <TextStyle>[
    caption,
    footnote,
    body,
    callout,
    title,
    title2,
    page,
    display,
    hero,
  ];
}

/// 手机的正文基线独立于系统辅助缩放，题目和大标题保持原有层级。
class AdaptiveTypography extends StatelessWidget {
  /// 包装应用及其浮层。
  const new({required this.child, super.key});

  /// 应用内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (media.size.width >= 600) return child;
    return MediaQuery(
      data: media.copyWith(textScaler: CompactTextScaler(media.textScaler)),
      child: child,
    );
  }
}

/// 将手机 14 磅正文提升至 16，再应用用户的系统缩放。
@immutable
class CompactTextScaler extends TextScaler {
  /// 保留系统文字缩放。
  const new(this.system);

  /// 系统提供的缩放规则。
  final TextScaler system;

  @override
  double scale(double fontSize) {
    final base = switch (fontSize) {
      <= 12 => fontSize + 1,
      <= 14 => fontSize + (fontSize == 14 ? 2 : 1),
      <= 16 => fontSize + 1,
      <= 18 => fontSize + 2,
      < 22 => fontSize + (22 - fontSize) / 2,
      _ => fontSize,
    };
    return system.scale(base);
  }

  @override
  double get textScaleFactor => scale(14) / 14;
}
