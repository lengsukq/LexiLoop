/// 桌面窗口初始化的 Web 实现。
///
/// 由 `desktop_window.dart` 条件导入选中。
///
/// **为什么是空实现而不是删掉调用点**：浏览器里窗口尺寸、位置与标题都由
/// 浏览器自身管理，网页无权设定（`window_manager` 也没有 web 实现）。
/// 保留同名函数是为了让 `lib/main.dart` 保持单一调用点——它只判断
/// `PlatformCaps.isDesktop`，而该值在 Web 上恒为 `false`，所以这个函数在
/// 浏览器里其实永远不会被调到，它存在的意义是让条件导入的两条分支类型一致。
library;

/// Web 端不需要（也无法）配置窗口。
Future<void> configureDesktopWindow() async {
  // 有意留空：见库级注释。浏览器标签页标题由 `MaterialApp.title` 负责。
}
