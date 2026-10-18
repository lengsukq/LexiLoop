/// 版面尺寸 token：页面正文列宽度、栏距与触控下限。
///
/// **为什么需要它**：在收敛「字号 / 圆角 / 间距」之前，全应用还漏了一族
/// 值——**版面宽度**。它没有出现在任何间距音阶里，因为它不是两个元素之间
/// 的距离，而是「内容允许长到多宽」。缺了这一族，收敛后仍然会看到：
///
/// * 1440 逻辑像素的窗口里，正文列 = 1440 − 256（侧边栏）− 40（栏距）
///   = 1144 像素，一整行释义要横跨 1144 像素才换行；
/// * 每个页面各自写 `EdgeInsets`，于是同一种「页面内边距」有 20 / 16 /
///   32 / 96 四种取值；
/// * 全仓只有 `game_shell.dart` 一处限宽，其余页面把卡片拉成一条长带。
///
/// 与 `LexiSpace` 的分工：`LexiSpace` 管**元素之间**的距离（2pt 节奏），
/// 这里管**内容区域**的边界。`LexiLayout` 的取值刻意不落在 2pt 节奏上，
/// 免得有人误把它当间距用。
///
/// 关于 `pageMaxWidth` 取 1040 的依据：默认窗口 1280 逻辑像素，减去
/// 256 侧边栏与 40 栏距后可用 984——小于 1040，因此**默认窗口下的渲染结果
/// 与限宽前完全一致**，改动不会带来「一打开就变窄」的回归；只有宽于
/// 约 1336 的窗口才开始看到居中留白。
library;

import 'package:flutter/widgets.dart';

/// 正文列宽度上限那个节点的 key。
///
/// **为什么需要一个可测的锚点**：`BoxConstraints(maxWidth: …)` 是声明，
/// 而「1440 像素的窗口里正文列到底多宽」才是用户看得见的结果。
/// 守卫测试要断言的是后者，量出来的宽度里已经含了侧边栏、栏距与居中
/// 的影响，靠数源码里的字面量是量不出来的。
///
/// 两处限宽（导航外壳的内容区、给顶层路由用的 `ContentWidthCap`）
/// 共用同一个 key，因此守卫可以对**每一条路由**用同一句话断言。
const Key contentCapKey = Key('app-content-cap');

/// 版面尺寸 token。
abstract final class LexiLayout {
  /// 普通页面正文列的宽度上限。
  ///
  /// 卡片、列表、统计格都按它收敛；超过就在内容区居中（不是靠左）。
  static const double pageMaxWidth = 1120;

  /// 沉浸式页面的内容宽度上限。
  ///
  /// 学习、游戏、配对、音标与各类表单属于这一类：屏幕上只有一个焦点，
  /// 把焦点摊到 1040 宽反而失去中心感。760–840 是「一张卡片 + 一行
  /// 按钮」仍然显得聚焦的区间。
  static const double immersiveMaxWidth = 840;

  /// 长文本（释义、例句、笔记、手动释义编辑器）的宽度上限。
  ///
  /// 中文与英文混排时，超过约 720 像素的一行会让眼睛丢失行首——
  /// 这是 Apple 在 `layout.md` 里说的「限制文本宽度以获得最佳可读性」
  /// （restrict the width of text for optimal readability）。
  static const double readingMaxWidth = 720;

  /// 页面栏距（左右内边距）。
  static const double pageGutter = 16;

  /// 宽窗口下的栏距。
  static const double pageGutterWide = 32;

  /// 双栏布局的宽度阈值。
  ///
  /// 注意它与侧边栏断点（1024）不是一回事：侧边栏断点决定**导航形态**，
  /// 这里决定**内容排布**。900 是「两栏各 440」仍然成立的宽度。
  static const double wideBreakpoint = 880;

  /// 同级卡片之间的默认间距。
  static const double cardGap = 16;

  /// 不同分区之间的间距。
  ///
  /// 区分 [cardGap] 与 [sectionGap] 是让「哪些卡片是一组」这件事可见的
  /// 最省力做法：收敛前首页 7 张卡片之间全是同一个 10，分组信息为零。
  static const double sectionGap = 32;

  /// 吸底动作区的高度下限。
  static const double stickyActionHeight = 56;

  /// 列表与表格行的高度下限。
  static const double rowHeight = 48;

  /// 标签列（键值对里的键）的宽度。
  ///
  /// 收敛前这里有 88（`DetailField.labelWidth`）、76（`_masteryLabelWidth`）
  /// 与 118（`_timestampColumnWidth`）三套，同一个页面里也会打架。
  static const double labelColumnWidth = 88;

  /// 可点区域的边长下限（逻辑像素）。
  ///
  /// 44 是触控热区的通行下限。此前它叫 `studyMinTapTarget` 并只住在学习
  /// 模块里，但它是**无障碍下限**，不是学习页的局部约定。
  static const double minTapTarget = 44;

  /// 主按钮的高度下限。
  static const double buttonHeight = 50;

  /// 页面在宽度受限时的水平栏距。
  static EdgeInsets guttersFor(double width) => EdgeInsets.symmetric(
    horizontal: width >= wideBreakpoint ? pageGutterWide : pageGutter,
  );
}
