/// WebDAV 多状态（207）响应的解析。
///
/// **为什么单独成文件且不依赖 `dio`**：`PROPFIND` 的响应形状是各家 WebDAV
/// 服务差异最大的地方（命名空间前缀、`href` 的编码、缺失字段）。把它做成
/// 纯函数之后，可以直接喂字符串断言，不必伪造 HTTP 层；真实样本也更容易
/// 加进回归用例。
///
/// **为什么按 `local name` 匹配而不是全名**：同一份 RFC 4918，
/// 群晖发 `<D:response>`、坚果云发 `<d:response>`、有的服务干脆不带前缀。
/// 匹配 `name.local` 对三者都成立。
///
/// **为什么 `href` 要过 [Uri]**：服务器会用百分号编码空格与中文，
/// 也可能给出绝对 URL（`https://h/dav/a%20b.json`）。先解析再取最后一段，
/// 由 `Uri` 负责解码，避免手写 `decodeURIComponent` 时漏掉 `+` 与双重编码。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:xml/xml.dart';

/// 解析 `PROPFIND` 响应，返回目录里的备份条目（按修改时间倒序）。
///
/// 非备份文件（不匹配 [backupFilePrefix] 或不是 `.json`）与子目录会被丢弃——
/// 用户的备份目录里可能同时放着别的东西，列出它们只会让「选一份恢复」变难。
List<RemoteBackupEntry> parseWebdavBackups(String xmlText) {
  final document = _tryParse(xmlText);
  if (document == null) return const <RemoteBackupEntry>[];

  final entries = <RemoteBackupEntry>[];
  for (final response in document.descendantElements) {
    if (response.name.local != 'response') continue;
    final entry = _entryOf(response);
    if (entry != null) entries.add(entry);
  }
  entries.sort(_byModifiedDesc);
  return List<RemoteBackupEntry>.unmodifiable(
    entries.take(webdavMaxListedBackups),
  );
}

/// 单个 `response` 节点转成条目；不是可行备份时返回 `null`。
RemoteBackupEntry? _entryOf(XmlElement response) {
  final name = _backupNameOf(response);
  if (name == null) return null;
  return RemoteBackupEntry(
    name: name,
    sizeBytes: _sizeOf(response),
    modifiedAt: _modifiedOf(response),
  );
}

/// 从 `href` 取文件名；不是本应用的备份时返回 `null`。
String? _backupNameOf(XmlElement response) {
  if (_isCollection(response)) return null;
  final href = _firstText(response, 'href');
  if (href == null) return null;
  final name = _fileNameOf(href);
  if (name == null) return null;
  if (!name.startsWith(backupFilePrefix)) return null;
  return name.endsWith('.json') ? name : null;
}

/// 该节点是否表示一个集合（目录）。
bool _isCollection(XmlElement response) {
  for (final element in response.descendantElements) {
    if (element.name.local != 'resourcetype') continue;
    for (final child in element.childElements) {
      if (child.name.local == 'collection') return true;
    }
  }
  return false;
}

/// 字节数；缺失或非数字时为 0。
int _sizeOf(XmlElement response) =>
    int.tryParse(_firstText(response, 'getcontentlength') ?? '') ?? 0;

/// 修改时间；缺失或无法解析时为 `null`。
DateTime? _modifiedOf(XmlElement response) =>
    parseWebdavTimestamp(_firstText(response, 'getlastmodified'));

/// 解析 WebDAV 的 `getlastmodified`。
///
/// 规范要求 RFC 1123（`Wed, 21 Oct 2015 07:28:00 GMT`），但 Dart 的
/// `DateTime.parse` **只认 ISO-8601**，直接喂进去会得到 `null`——于是所有条目
/// 的修改时间都会静默变成空值，排序退化成「按文件名」。这里显式处理
/// RFC 1123，并兼容部分服务直接返回 ISO-8601 的情况。
DateTime? parseWebdavTimestamp(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();
  final match = _rfc1123Pattern.firstMatch(text);
  if (match == null) return null;
  final month = _monthNumbers[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

/// `href` 里的文件名（已解码）。
String? _fileNameOf(String href) {
  final uri = Uri.tryParse(href.trim());
  if (uri == null) return null;
  // 目录的 href 以 `/` 结尾，取 segment 会拿到最后一段文件名或空串。
  for (final segment in uri.pathSegments.reversed) {
    if (segment.isNotEmpty) return segment;
  }
  return null;
}

/// 取第一个指定 local name 的元素的文本。
String? _firstText(XmlElement root, String localName) {
  for (final element in root.descendantElements) {
    if (element.name.local != localName) continue;
    return element.innerText.trim();
  }
  return null;
}

/// 容错解析：服务器偶尔会发出不严格合法的 XML，此时按「空目录」处理。
XmlDocument? _tryParse(String xmlText) {
  try {
    return XmlDocument.parse(xmlText);
  } on XmlException {
    return null;
  }
}

/// 修改时间倒序；缺失时间的排在最后，同时间按名字倒序。
int _byModifiedDesc(RemoteBackupEntry a, RemoteBackupEntry b) {
  final left = a.modifiedAt;
  final right = b.modifiedAt;
  if (left != null && right != null) {
    final byTime = right.compareTo(left);
    if (byTime != 0) return byTime;
  } else if (left != null) {
    return -1;
  } else if (right != null) {
    return 1;
  }
  return b.name.compareTo(a.name);
}

/// RFC 1123 日期：`Wed, 21 Oct 2015 07:28:00 GMT`。
final RegExp _rfc1123Pattern = RegExp(
  r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
);

/// 英文月份缩写到月份号。
const Map<String, int> _monthNumbers = <String, int>{
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
