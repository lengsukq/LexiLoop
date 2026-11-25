/// 局域网共享服务端的 `dart:io` 实现。
///
/// 只做协议层的事：监听 TCP 端口、校验配对码、按需导出一份备份写进响应、
/// 以及在 UDP 上应答发现查询。**它不认识会话状态、不认识设置表**——
/// 「谁在共享、配对码是什么、错码多少次之后要停」都由
/// `lib/services/lan_sync/lan_sync_share_service.dart` 编排。
///
/// **只读**：这里没有、也不会有一个写端点。整个特性的破坏性动作只发生在
/// 对端本机（导出 → 全量替换），远端请求永远只能读到一份备份。
///
/// 本文件是 `dart:io` 的合法居所之一（架构守卫要求它只出现在
/// `*_native.dart` 里），由 `lan_sync_host.dart` 条件导出。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_codec_native.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_ws_host_native.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 启动共享服务端。
///
/// **同时绑两个端口**：TCP 用于握手与下载，UDP 用于应答发现。任一个绑定失败
/// 都视为「启动失败」——只有 TCP 时对端根本找不到我们，让用户看到
/// 「已开启共享」却永远搜不到，比直接报错更糟。
Future<LanSyncHost> createLanSyncHost(LanSyncHostOptions options) async {
  final server = await _bindHttp(options);
  final RawDatagramSocket discovery;
  try {
    discovery = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      options.discoveryPort,
    );
  } on SocketException catch (error) {
    await server.close(force: true);
    throw ExternalServiceError(
      AppErrorCode.lanSyncHostStartFailed,
      details: 'UDP $lanSyncDiscoveryPort 绑定失败：${error.message}',
    );
  }
  // **用实际绑定到的端口，而不是 `options.port`**：传 0 时由系统分配一个
  // 空闲端口，此时把 0 报给对方等于报了一个谁都连不上的地址。
  return _HttpLanSyncHost(
    server,
    discovery,
    options,
    await _localBaseUri(server.port),
  )..listen();
}

/// 绑定 TCP 端口；失败归一成「无法启动共享」。
Future<HttpServer> _bindHttp(LanSyncHostOptions options) async {
  try {
    return await HttpServer.bind(InternetAddress.anyIPv4, options.port);
  } on SocketException catch (error) {
    throw ExternalServiceError(
      AppErrorCode.lanSyncHostStartFailed,
      details: 'TCP ${options.port} 绑定失败：${error.message}',
    );
  }
}

/// 本机第一张非环回 IPv4 网卡的地址拼出的根地址。
///
/// **只用于界面展示**：告诉用户「让对方连这个地址」，而真正的连接地址由对端
/// 从发现报文的来源地址得到。因此取不到网卡地址时只回落到环回地址，
/// 不中断启动——否则一台网卡枚举异常的机器会连共享都开不起来。
Future<Uri> _localBaseUri(int port) async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback) continue;
        return Uri.parse('http://${address.address}:$port/');
      }
    }
  } on SocketException {
    // 枚举网卡失败只影响展示用的那个地址，服务本身照常可用。
  }
  return Uri.parse('http://${InternetAddress.loopbackIPv4.address}:$port/');
}

/// `dart:io` 的共享服务端。
class _HttpLanSyncHost implements LanSyncHost {
  /// 以已绑定的两个套接字与选项构造。
  ///
  /// 用位置参数而不是具名参数：字段是私有的，而 Dart 禁止下划线开头的
  /// 具名参数；写成 `this._server` 的位置初始化形参才能既满足
  /// `prefer_initializing_formals`，又不必另起一个公开字段名。
  new(this._server, this._discovery, this._options, this.baseUri);

  final HttpServer _server;
  final RawDatagramSocket _discovery;
  final LanSyncHostOptions _options;

  @override
  final Uri baseUri;

  StreamSubscription<HttpRequest>? _requests;
  StreamSubscription<RawSocketEvent>? _datagrams;
  int _served = 0;
  int _failures = 0;
  bool _busy = false;
  bool _stopped = false;

  @override
  int get servedCount => _served;

  /// 开始接收请求与数据报。由 [createLanSyncHost] 在返回前调用一次。
  void listen() {
    _requests = _server.listen(_onRequest);
    // **必须挂 onError**：`send` 的目标地址可能不可路由（对端在一张已经
    // 下线的接口或某张容器网桥上），此时套接字把失败**异步**报进事件流，
    // 而不是从 `send` 里抛出（已实测）。没有这个回调，一条回不出去的应答
    // 就会变成未捕获异常，而共享会话本身毫无问题。
    _datagrams = _discovery.listen(
      _onDatagram,
      onError: (Object error) {
        // 应答是尽力而为的：对端收不到会走自己的搜索超时，
        // 届时它看到「没搜到设备」，主机这边没有任何需要修复的状态。
      },
    );
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _requests?.cancel();
    await _datagrams?.cancel();
    _discovery.close();
    await _server.close(force: true);
  }

  /// 分派一个 HTTP 请求。
  ///
  /// **任何异常都不外泄**：单个请求的失败不该让共享会话退出——主机是纯被动的
  /// 一方，用户没有「重试」这个动作可做，只能重新开一次共享。
  Future<void> _onRequest(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        return await _reject(
          request,
          HttpStatus.methodNotAllowed,
          AppErrorCode.lanSyncRequestFailed,
        );
      }
      return switch (request.uri.path) {
        lanSyncHandshakePath => await _handshake(request),
        lanSyncBackupPath => await _backup(request),
        lanSyncSessionPath => await _session(request),
        _ => await _reject(
          request,
          HttpStatus.notFound,
          AppErrorCode.lanSyncNotSharing,
        ),
      };
    } on Object {
      // 尽力回一个 500，让对端拿到可读的状态码而不是一个断掉的连接。
      await _reject(
        request,
        HttpStatus.internalServerError,
        AppErrorCode.lanSyncRequestFailed,
      );
    }
  }

  /// 握手：只验码，不传数据。
  Future<void> _handshake(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      return await _reject(
        request,
        HttpStatus.unauthorized,
        AppErrorCode.lanSyncCodeInvalid,
      );
    }
    final handshake = LanSyncHandshake(
      deviceName: _options.deviceName,
      protocolVersion: lanSyncProtocolVersion,
      deviceId: _options.deviceId,
      deviceKind: _options.deviceKind,
      allowsBidirectional: _options.allowsBidirectional,
      datasetEpoch: _options.datasetEpoch,
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(handshake.toJsonBody());
    await request.response.close();
  }

  /// v2 WebSocket 双向增量与双端实时进度会话。
  Future<void> _session(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      return await _reject(
        request,
        HttpStatus.unauthorized,
        AppErrorCode.lanSyncCodeInvalid,
      );
    }
    final delegate = _options.sessionDelegate;
    if (delegate == null) {
      return await _reject(
        request,
        HttpStatus.notFound,
        AppErrorCode.lanSyncNotSharing,
      );
    }
    if (_busy) {
      return await _reject(
        request,
        HttpStatus.conflict,
        AppErrorCode.lanSyncBusy,
      );
    }
    await _runUpgradedSession(request, delegate);
  }

  Future<void> _runUpgradedSession(
    HttpRequest request,
    LanSyncSessionDelegate delegate,
  ) async {
    _busy = true;
    try {
      // 载荷本身已在后台 Isolate 做过 GZip 压缩，关闭 WebSocket 层 permessage-deflate
      // 避免二次压缩开销与大二进制分片状态异常。
      final socket = await WebSocketTransformer.upgrade(
        request,
        compression: CompressionOptions.compressionOff,
      );
      socket.pingInterval = const Duration(
        milliseconds: lanSyncWsPingIntervalMs,
      );
      final peerIp = request.connectionInfo?.remoteAddress.address ?? '';
      await runLanSyncHostSession(
        socket: socket,
        delegate: delegate,
        localEndpoint: LanSyncEndpoint(
          name: _options.deviceName,
          deviceKind: _options.deviceKind,
          address: baseUri.authority,
        ),
        peerAddress: peerIp,
      );
      _served += 1;
      _options.onServed(_served);
    } on Object {
      // 会话内错误已通过 WebSocket 帧与 onSessionProgress 通知双方，主机继续保活。
    } finally {
      _busy = false;
    }
  }

  /// 拉取一份备份。
  ///
  /// 同一时刻只服务一个请求：导出一次 27MB 已经要吃满 I/O，
  /// 两个并发请求只会让两边都慢，且内存里同时存在两份备份。
  Future<void> _backup(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      return await _reject(
        request,
        HttpStatus.unauthorized,
        AppErrorCode.lanSyncCodeInvalid,
      );
    }
    if (_busy) {
      return await _reject(
        request,
        HttpStatus.conflict,
        AppErrorCode.lanSyncBusy,
      );
    }
    _busy = true;
    try {
      await _writeBackup(request);
    } on AppError catch (error) {
      await _reject(request, _statusFor(error.code), error.code);
    } finally {
      _busy = false;
    }
  }

  /// 导出并写出响应体（客户端声明 `Accept-Encoding: gzip` 时走后台 GZip 压缩）。
  Future<void> _writeBackup(HttpRequest request) async {
    final backup = await _options.backupSource();
    if (backup.bytes.length > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '待共享的备份 ${backup.bytes.length} 字节，上限 $maxBackupBytes',
      );
    }
    final acceptGzip = _acceptsGzip(request);
    final wireBytes = acceptGzip
        ? await compressLanSyncBytes(backup.bytes)
        : backup.bytes;
    final response = request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..headers.set(lanSyncBackupNameHeader, backup.fileName)
      ..headers.set(lanSyncBackupRowsHeader, '${backup.totalRows}');
    if (acceptGzip) {
      response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    }
    response
      ..contentLength = wireBytes.length
      ..add(wireBytes);
    _served += 1;
    _options.onServed(_served);
    _busy = false;
    await response.close();
  }

  bool _acceptsGzip(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.acceptEncodingHeader);
    return header != null && header.toLowerCase().contains('gzip');
  }

  /// 配对码是否正确；连续错码到达上限时停掉共享。
  ///
  /// **成功会清零计数**：合法用户偶尔敲错一次不该在几小时后被自己之前的
  /// 手误踢下线。计数只在「一直错」的情况下才累加。
  bool _isAuthorized(HttpRequest request) {
    final provided = request.headers.value(lanSyncCodeHeader);
    if (provided != null && provided == _options.pairingCode) {
      _failures = 0;
      return true;
    }
    _failures += 1;
    if (_failures >= lanSyncPairingCodeMaxAttempts) {
      _options.onCodeLockout();
      unawaited(stop());
    }
    return false;
  }

  /// 错误码对应的 HTTP 状态码。
  int _statusFor(AppErrorCode code) => switch (code) {
    AppErrorCode.backupTooLarge => lanSyncStatusTooLarge,
    _ => HttpStatus.internalServerError,
  };

  /// 写一个只带错误码的失败响应。
  ///
  /// **永不抛出**：对端可能已经断开（用户取消、切网），此时写响应本身会失败，
  /// 而这不影响主机继续服务下一个请求。
  Future<void> _reject(
    HttpRequest request,
    int status,
    AppErrorCode code,
  ) async {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(lanSyncErrorBody(code.code));
      await request.response.close();
    } on Object {
      // 连接已经断了，回什么都不可能送达；共享会话继续。
    }
  }

  /// 收一条 UDP 报文。
  void _onDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    try {
      final datagram = _discovery.receive();
      if (datagram != null) _replyToDiscovery(datagram);
    } on Object {
      // 一条畸形的报文不该让发现应答器停摆：丢掉它，等下一条。
    }
  }

  /// 实际绑定到的端口。
  int get _port => _server.port;

  /// 是一条本协议的查询就单播回一条应答。
  ///
  /// 单播而不是广播：广播回复会让同网段每台机器都解析一份与自己无关的报文，
  /// 而提问的只有一台。
  void _replyToDiscovery(Datagram datagram) {
    if (!_isDiscoveryQuery(datagram.data)) return;
    // 来源是「未指定地址」时回不出去，直接丢掉而不是让内核报一次错。
    if (datagram.address.address == lanSyncUnspecifiedAddress) return;
    final reply = DiscoveredLanHost(
      instanceId: _options.instanceId,
      deviceName: _options.deviceName,
      address: datagram.address.address,
      port: _port,
      protocolVersion: lanSyncProtocolVersion,
      deviceKind: _options.deviceKind,
      allowsBidirectional: _options.allowsBidirectional,
    ).toWire();
    _discovery.send(
      utf8.encode(jsonEncode(reply)),
      datagram.address,
      datagram.port,
    );
  }

  /// 报文是否是**本版本**的发现查询。
  ///
  /// 版本也参与判定：一台旧版设备的查询用新版的字段解读只会得到一堆空值，
  /// 直接不回应比回一个对方读不懂的应答更省事。
  bool _isDiscoveryQuery(Uint8List data) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data));
    } on FormatException {
      return false;
    }
    if (decoded is! Map) return false;
    return decoded['service'] == lanSyncServiceName &&
        decoded['kind'] == lanSyncDiscoveryQueryKind &&
        decoded['version'] == lanSyncProtocolVersion;
  }
}
