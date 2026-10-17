/// 远端备份存储的抽象端口。
///
/// **为什么要这层接口**：与 `HttpFetcher`、`AudioDownloadPort`、`SpeechEngine`
/// 同一套约定——把「协议与平台」挡在业务逻辑之外。上传、恢复、自动备份三个
/// 服务只依赖这 4 个方法，测试里一个内存实现就能覆盖全部分支，
/// 不必真的跑一台 WebDAV 服务器，也不必伪造 HTTP 层。
library;

import 'dart:typed_data';

import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

/// 远端备份存储。
///
/// 失败一律抛业务错误（`lib/core/errors.dart` 的 `AppError`），由调用方决定文案；
/// 未配置凭据时不应构造本接口的实现。
abstract interface class RemoteBackupClient {
  /// 确保备份目录存在（不存在则逐级创建）。
  ///
  /// 幂等：目录已存在时什么都不做。上传前必须先调它——
  /// `PUT` 到一个不存在的目录会得到 409，而各服务对「自动建目录」的支持不一。
  Future<void> ensureDirectory();

  /// 上传一份备份。同名对象会被覆盖（本应用的命名带秒级时间戳）。
  Future<void> putBackup({required String fileName, required Uint8List bytes});

  /// 列出备份目录里的备份（按修改时间倒序，最多 `webdavMaxListedBackups` 条）。
  Future<List<RemoteBackupEntry>> listBackups();

  /// 下载指定备份的全部字节。
  ///
  /// 超过 `maxBackupBytes` 时必须拒绝，而不是把整个响应读进内存。
  Future<Uint8List> downloadBackup(RemoteBackupEntry entry);
}

/// 按当前凭据构造客户端的工厂。
///
/// **为什么传工厂而不是客户端实例**：自动备份每次醒来都要用**当时**的设置，
/// 用户在两次备份之间改了地址或密码必须立刻生效。若把客户端实例注入服务，
/// 服务就永久握着旧凭据（旧客户端里连认证头都是老的）。
typedef RemoteBackupClientFactory = RemoteBackupClient Function(
  WebdavCredential credential,
);
