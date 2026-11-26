/// 页面外壳：唯一的页面容器。
///
/// **为什么必须有它**：在它之前，每个页面都自己写「页头 + 滚动区 + 底部
/// 动作」这三件事，于是同一件事出现了多种写法——
///
/// | 事实 | 收敛前 |
/// |---|---|
/// | 根容器 | 9 个页面写 `Scaffold`，3 个（统计 / 添加 / 初始化）完全不写 |
/// | 页头 | `AppBar` 只有 2 处，其余全是各页手写的 `Column + Text` |
/// | 左右内边距 | 20 / 16 / 32 / 96 四种取值 |
/// | 正文宽度上限 | 全仓只有 `games/widgets/game_shell.dart` 一处（760） |
///
/// 后果不是「不好看」这么抽象：1440 逻辑像素的窗口里，正文列宽
/// 1440 − 256（侧边栏）− 40（栏距）= 1144 像素，一整行释义要横跨
/// 1144 像素才换行，而卡片里的内容仍然只有 200 像素——右边 900 像素
/// 全是空的。这就是「拉成一条长带」。
///
/// 因此本构件只做三件事，并强制它们对全部页面同构：
///
/// 1. **限宽并居中**：宽度上限来自 [LexiLayout]，见 `lexi_layout.dart`；
/// 2. **提供 `Material` 祖先**：页面不必各自 `Scaffold`，`InkWell` /
///    `TextField` / `ListTile` 都能向上找到宿主；
/// 3. **吸底动作区**：主按钮固定在同一个位置，且滚动区自动补足底部
///    内边距，不会被动作条盖住。
///
/// **不负责背景**：环境光斑（`AmbientBackground`）由导航外壳统一绘制一次。
/// 页面自己再叠一层会出现「双层光斑」，沉浸页尤其明显。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 一份解析完的内边距。
///
/// 内部类型：`PageShell` 需要把「页头已经吃掉的顶部」从正文里扣掉，
/// 因此必须拿到四个具体数值，而不是一个 `EdgeInsetsGeometry`。
@immutable
class _Padding {
  const new(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// 页面外壳。
class PageShell extends StatelessWidget {
  /// 以正文、可选页头与可选吸底动作构造。
  const new({
    required this.child,
    this.header,
    this.bottomAction,
    this.maxWidth = LexiLayout.pageMaxWidth,
    this.scrollable = false,
    super.key,
  });

  /// 页面正文。
  ///
  /// [scrollable] 为真时会被放进一个自带滚动条的滚动区；
  /// 为假时按原样放在页头与动作区之间（由调用方自管滚动，
  /// 例如「固定筛选栏 + 只滚列表」的单词本页）。
  final Widget child;

  /// 页头；为空时不占位置。
  final Widget? header;

  /// 吸底动作区。
  ///
  /// 传进来的内容会被套上吸底容器的内边距与分隔线；通常只放一个
  /// 主按钮（见 `docs/DESIGN_SYSTEM.md` 的「动作与确认分级」）。
  final Widget? bottomAction;

  /// 正文宽度上限。
  final double maxWidth;

  /// 是否由外壳提供滚动区。
  final bool scrollable;

  /// 左右栏距。
  static const double _gutter = LexiLayout.pageGutter;

  /// 正文顶部内边距（有页头时由页头承担）。
  static const double _top = LexiSpace.s16;

  /// 正文底部内边距。
  static const double _bottom = LexiSpace.s32;

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width < 600
        ? _gutter
        : LexiLayout.pageGutterWide;
    final pagePadding = _Padding(gutter, _top, gutter, _bottom);
    // 页头已经吃掉了顶部，正文只保留左右与底部。
    final bodyPadding = header == null
        ? pagePadding
        : _Padding(gutter, 0, gutter, _bottom);

    // **必须是真的 `Scaffold`，不能只给一个 `Material`**：
    // `ScaffoldMessenger.showSnackBar` 需要「当前有后代 Scaffold」才能挂上去，
    // 只有 Material 时它会在 debug 下断言失败（`_scaffolds.isNotEmpty`），
    // 于是词条详情页的「已排入补全队列」这类提示全都不再出现。
    // 透明底 + 不缩底部：外壳已经画了背景，这里只提供一个宿主。
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (header != null)
                        Padding(padding: _insets(pagePadding), child: header),
                      Expanded(child: _body(bodyPadding)),
                    ],
                  ),
                ),
              ),
            ),
            if (bottomAction != null)
              _BottomActionBar(
                maxWidth: maxWidth,
                gutter: gutter,
                child: bottomAction!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(_Padding padding) {
    final insets = _insets(padding);
    if (!scrollable) return Padding(padding: insets, child: child);
    return Scrollbar(
      child: SingleChildScrollView(padding: insets, child: child),
    );
  }

  EdgeInsets _insets(_Padding value) =>
      EdgeInsets.fromLTRB(value.left, value.top, value.right, value.bottom);
}

/// 吸底动作条：浮在内容之上的圆角卡片。
///
/// 不复用「整条白底 + 顶部分隔线」：那条横幅在宽窗口下会变成一块
/// 与页面同宽的白板，和内容卡片的圆角语言断裂。这里让它成为一张
/// 有影的浮动卡，内容与动作条用同一个栏距。
class _BottomActionBar extends StatelessWidget {
  const new({
    required this.child,
    required this.maxWidth,
    required this.gutter,
  });

  final Widget child;
  final double maxWidth;

  /// 与正文相同的左右栏距。
  ///
  /// 固定写 16 会让动作条在宽窗口下比正文各宽 16 像素：学习页的四档自评
  /// 正好压在这条错位上，看起来像「底部那排没对齐」。这里接收
  /// [PageShell] 已经解析好的栏距，正文与动作条用同一个值。
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          LexiSpace.s8,
          gutter,
          LexiSpace.s8,
        ),
        child: Align(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Surface(
              variant: SurfaceVariant.raised,
              borderRadius: BorderRadius.circular(LexiRadius.xl),
              padding: const EdgeInsets.symmetric(
                horizontal: LexiSpace.s16,
                vertical: LexiSpace.s8,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: LexiLayout.stickyActionHeight,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 给**不在导航外壳里**的顶层路由套上与外壳一致的版心。
///
/// `/import`、`/article`、`/games`、`/match` 是顶层路由：它们独占屏幕
/// （外壳刻意不参与，见 `app/router.dart` 的说明），因此拿不到
/// `AdaptiveShell` 在内容区做的限宽。少了这一步，只有这四条路由会在
/// 宽窗口下把内容拉成一条长带——而它们恰好是信息密度最高的四条。
///
/// 它只做「限宽 + 居中 + 撑满」三件事，不提供 `Material`、`SafeArea`
/// 或滚动：那些页面各自有 `Scaffold` 与滚动结构，塞进来的话就重复了。
class ContentWidthCap extends StatelessWidget {
  /// 以正文与宽度上限构造。
  const new({
    required this.child,
    this.maxWidth = LexiLayout.pageMaxWidth,
    super.key,
  });

  /// 正文。
  final Widget child;

  /// 宽度上限。
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      key: contentCapKey,
      constraints: BoxConstraints(maxWidth: maxWidth),
      // 松约束下 `Column` 会缩到最宽子节点，卡片宽度于是跟着内容走；
      // 显式撑满才能让「版心」这个概念成立。
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
