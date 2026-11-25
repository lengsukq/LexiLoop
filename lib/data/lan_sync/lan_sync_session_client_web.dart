/// Web 端局域网 v2 会话占位实现。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client_port.dart';

/// 在 Web 上永远抛「不支持」。
Future<LanSyncSessionOutcome> runLanSyncClientSession(
  LanSyncSessionRequest request,
) async {
  throw const ValidationError(AppErrorCode.lanSyncUnsupported);
}
