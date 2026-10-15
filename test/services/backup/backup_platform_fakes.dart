/// 备份交付测试用的平台替身。
///
/// **为什么必须替换**：`share_plus` / `path_provider` / `file_picker` 在
/// `flutter test` 进程里没有可用的原生实现，直接调用会抛
/// `MissingPluginException`，于是这些路径只能在真机上验证。三个替身分别接管
/// 「分享面板」「临时目录」「文件选择器」，让备份交付的两条分支都能在 VM 上
/// 跑起来。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

/// 记录被交付内容的分享面板替身。
///
/// **必须在整个测试文件里复用同一个实例**：`SharePlus.instance` 是
/// `static final`，第一次访问时就把当时的 `SharePlatform.instance` 固定下来，
/// 之后在 `setUp` 里换新实例不会生效。所以由测试文件创建一次，
/// `setUp` 只清空 [calls]。
final class FakeSharePlatform extends SharePlatform {
  /// 每次 `share` 收到的参数，按调用顺序。
  final List<ShareParams> calls = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return ShareResult.unavailable;
  }
}

/// 临时目录替身：把 `getTemporaryPath()` 指向一个真实存在的目录。
///
/// 用真实目录而不是内存文件系统，是为了让「落盘内容与导出字节相同」这条
/// 断言能真的读到文件。
final class FakePathProviderPlatform extends PathProviderPlatform {
  /// 以 `getTemporaryPath()` 要返回的路径构造。
  new(this.temporaryPath);

  /// `getTemporaryPath()` 的返回值。
  final String temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

/// 没有本地路径的「云文件」替身。
///
/// `uri` 用 `blob:` 协议，于是 [PlatformFile.path] 为 `null`——这正是 Android
/// 的 `content://` 与浏览器里 file_picker 的形态，也是旧实现
/// `File(files.first.path!)` 会在两端崩掉的输入。
final class CloudPlatformFile extends PlatformFile {
  /// 以文件名与内容构造。
  new({required this.name, required this.bytes});

  @override
  final String name;

  /// 文件的全部字节，也是 `readAsBytes()` 的返回值。
  final Uint8List bytes;

  @override
  Uri get uri => Uri.parse('blob:http://localhost/$name');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream<Uint8List>.value(bytes);
}

/// 文件选择器替身：返回预设的文件列表，并记录收到的筛选条件。
final class FakeFilePickerPlatform extends FilePickerPlatform {
  /// 以 `pickFiles` 要返回的文件列表构造。
  new(this.files);

  /// `pickFiles` 要返回的文件。
  final List<PlatformFile> files;

  /// 最近一次 `pickFiles` 收到的对话框标题。
  String? lastDialogTitle;

  /// 最近一次 `pickFiles` 收到的扩展名白名单。
  List<String>? lastAllowedExtensions;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    lastDialogTitle = dialogTitle;
    lastAllowedExtensions = allowedExtensions;
    return files;
  }
}
