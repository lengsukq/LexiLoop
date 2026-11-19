/// 顶层路由与子路由的路径常量。
///
/// 集中在 `lib/ui/navigation/` 供全仓引用，避免各模块硬编码路径字符串。
library;

/// 首页（今日）。
const String homePath = '/';

/// 学习页；用 `?mode=` 指定模式。
const String studyPath = '/study';

/// 词库页（单词本）。
const String wordsPath = '/words';

/// 词条详情的前缀；后接词条 ID。
const String wordDetailPathPrefix = '/words/';

/// 添加词条页。
const String addPath = '/add';

/// 初始化队列页（后台补全明细）。
const String initializePath = '/initialize';

/// 统计页。
const String statisticsPath = '/statistics';

/// 设置页。
const String settingsPath = '/settings';

/// 音标辨音页。
const String phoneticsPath = '/phonetics';

/// CSV 导入页。
const String csvImportPath = '/import';

/// 粘贴文章页。
const String articlePath = '/article';

/// 小游戏页。
const String gamesPath = '/games';

/// 限时配对页。
const String matchPath = '/match';
