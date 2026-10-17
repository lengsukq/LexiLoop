/// 测试用的空闲 UDP 端口。
///
/// **为什么不写死端口号**：局域网同步的两组用例（主机应答发现、客户端广播发现）
/// 各自要起 UDP 套接字，而 `flutter test` 默认并发跑多个文件——同一进程内写死
/// 同一个端口会让其中一个用例 bind 失败，表现为「某个文件莫名加载不起来」。
/// 反过来按时间戳取端口也只是把碰撞概率降低。
///
/// 先绑一个 0 端口的套接字、读到系统分配的真实端口再放掉，是唯一能
/// 真正避开已被占用端口做法。
library;

import 'dart:io';

/// 取一个当前空闲的 UDP 端口。
///
/// 归还到真正被测试绑定之间有一个极短的窗口，但同一台机器上不会有别的进程
/// 恰好在这一刻抢走一个刚被释放的高位端口。
Future<int> freeUdpPort() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  socket.close();
  return port;
}
