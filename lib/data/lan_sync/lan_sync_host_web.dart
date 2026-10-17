/// 局域网同步在 Web 上的占位实现。
///
/// 由 `lan_sync_host.dart` 条件导入选中。浏览器里既不能监听端口也不能发 UDP
/// 广播，因此这里没有「降级实现」可做——唯一正确的行为是明确告诉用户
/// 换一个平台，与 `browserCorsBlocked` 的处理方式一致。
///
/// 界面层会在 Web 上直接把整个分组禁用（见 `LanSyncSection`），
/// 所以这个函数正常路径下不会被调到；它存在是为了让「不小心调到了」
/// 得到一句可读的错误，而不是一个编译不过的 Web 构建。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';

/// 在 Web 上永远失败。
Future<LanSyncHost> createLanSyncHost(LanSyncHostOptions options) async {
  throw const ValidationError(AppErrorCode.lanSyncUnsupported);
}
