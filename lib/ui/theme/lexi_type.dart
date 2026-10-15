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
  /// 11 磅：徽标、计数、间隔预览等最小号文字。
  ///
  /// 这是 macOS 的可读下限之上的一档；再小就只能靠颜色硬撑对比度了。
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );

  /// 12 磅：次要说明、音标、字段标签。
  static const TextStyle footnote = TextStyle(fontSize: 12, height: 16 / 12);

  /// 13 磅：正文默认档，等同 macOS 的 body。
  static const TextStyle body = TextStyle(fontSize: 13, height: 18 / 13);

  /// 15 磅：选项标签、需要被强调的正文。
  static const TextStyle callout = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
  );

  /// 17 磅：卡片标题。
  static const TextStyle title = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
  );

  /// 22 磅：区块标题。
  static const TextStyle title2 = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
  );

  /// 26 磅：页面标题。
  static const TextStyle page = TextStyle(
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// 30 磅：学习页的词条主视觉、词条详情的词条。
  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  /// 34 磅：仪表盘与结算页的大数字。
  static const TextStyle hero = TextStyle(
    fontSize: 34,
    height: 40 / 34,
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
