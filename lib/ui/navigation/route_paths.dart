/// 顶层路由与子路由的路径常量。
///
/// **为什么单独一个文件**：这些路径被多个 feature 引用（词库卡片、首页空态、
/// 初始化队列、游戏结算、设置页），而它们的定义原本散在各自的页面文件里——
/// `router.dart` 里一份、`words_page.dart` 里一份、`dashboard_page.dart` 里
/// 又抄了一份，还留下一段「为什么不复用」的注释。字符串常量没有编译器保护，
/// 抄三份就迟早会改错一份。
///
/// 放在 `lib/ui/navigation/` 而不是 `lib/app/`：feature 层引用 `app/router.dart`
/// 会把整个路由表（以及它 import 的全部页面）拉进依赖图，而这里只是几个字符串。
library;

/// CSV 导入页（顶层路由，不套外壳）。
const String csvImportPath = '/import';

/// 粘贴文章页（顶层路由，不套外壳）。
const String articlePath = '/article';

/// 小游戏页（顶层路由，不套外壳）。
const String gamesPath = '/games';

/// 限时配对页（顶层路由，不套外壳）。
const String matchPath = '/match';

/// 音标辨音页（顶层路由，不套外壳）。
const String phoneticsPath = '/phonetics';

/// 词条详情的前缀；后接词条 ID。
const String wordDetailPathPrefix = '/words/';

/// 词库页。
const String wordsPath = '/words';

/// 初始化队列页。
const String initializePath = '/initialize';

/// 学习页；用 `?mode=` 指定模式。
const String studyPath = '/study';
