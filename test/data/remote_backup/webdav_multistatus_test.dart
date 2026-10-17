/// `PROPFIND` 响应解析与时间戳解析的测试。
///
/// 用的是各家 WebDAV 服务的**真实形状**：不同命名空间前缀、绝对 / 相对
/// `href`、百分号编码、缺失属性、以及目录自身的条目。
/// 这些都是「换一台服务器就静默列不出备份」的常见原因。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/remote_backup/webdav_multistatus.dart';

/// 一份典型的备份文件名（与真实导出的命名逐字一致）。
const String _backupName = 'lexiloop-backup-2026-10-16-101500.json';

/// 文件名里带空格、需要百分号编码的那份。
const String _spacedName = 'lexiloop-backup-2026-10-16 101500.json';

/// 一条 `response` 节点。
String _response({
  required String href,
  String? modified,
  String? size,
  bool collection = false,
}) {
  final type = collection
      ? '<d:resourcetype><d:collection/></d:resourcetype>'
      : '<d:resourcetype/>';
  final length = size == null
      ? ''
      : '<d:getcontentlength>$size</d:getcontentlength>';
  final lastModified = modified == null
      ? ''
      : '<d:getlastmodified>$modified</d:getlastmodified>';
  return '<d:response><d:href>$href</d:href><d:propstat><d:prop>$type'
      '$length$lastModified</d:prop></d:propstat></d:response>';
}

/// 把若干条 `response` 包成一份 `multistatus`。
String _multistatus(List<String> responses, {String prefix = 'D'}) =>
    '<$prefix:multistatus xmlns:$prefix="DAV:">'
    '${responses.join()}'
    '</$prefix:multistatus>';

void main() {
  group('时间戳', () {
    test('RFC 1123（规范的 getlastmodified）能解析', () {
      final parsed = parseWebdavTimestamp('Wed, 21 Oct 2015 07:28:00 GMT');

      expect(parsed, DateTime.utc(2015, 10, 21, 7, 28));
      expect(parsed!.isUtc, isTrue);
    });

    test('ISO-8601（部分服务的实际输出）也能解析并转成 UTC', () {
      expect(
        parseWebdavTimestamp('2026-10-16T03:28:15+08:00'),
        DateTime.utc(2026, 10, 15, 19, 28, 15),
      );
    });

    test('无法解析时返回 null，而不是抛异常', () {
      expect(parseWebdavTimestamp('不是时间'), isNull);
      expect(parseWebdavTimestamp(''), isNull);
      expect(parseWebdavTimestamp(null), isNull);
    });
  });

  group('多状态解析', () {
    test('只收本应用的 .json 备份，丢掉目录与无关文件', () {
      final xml = _multistatus(<String>[
        _response(href: '/b/', collection: true),
        _response(
          href: '/b/$_backupName',
          size: '1024',
          modified: 'Thu, 15 Oct 2026 20:49:09 GMT',
        ),
        _response(href: '/b/notes.txt', size: '10'),
      ]);

      final entries = parseWebdavBackups(xml);

      expect(entries, hasLength(1));
      expect(entries.single.name, _backupName);
      expect(entries.single.sizeBytes, 1024);
      expect(entries.single.modifiedAt, DateTime.utc(2026, 10, 15, 20, 49, 9));
    });

    test('小写前缀、绝对 href、百分号编码的文件名都能认出', () {
      final xml = _multistatus(<String>[
        _response(href: 'https://h/b/$_backupName', size: '2048'),
        _response(
          href: '/b/${_spacedName.replaceAll(' ', '%20')}',
          size: '4096',
        ),
      ], prefix: 'd');

      final entries = parseWebdavBackups(xml);

      // 两者都没有修改时间，于是退化成按文件名倒序：空格（0x20）
      // 小于连字符（0x2D），所以带连字符的那份排在前面。
      expect(entries.map((entry) => entry.name).toList(), <String>[
        _backupName,
        _spacedName,
      ]);
    });

    test('按修改时间倒序，缺时间戳的排在最后', () {
      final xml = _multistatus(<String>[
        _response(
          href: '/b/lexiloop-backup-2026-10-14-000000.json',
          modified: 'Tue, 14 Oct 2026 00:00:00 GMT',
        ),
        _response(
          href: '/b/lexiloop-backup-2026-10-16-000000.json',
          modified: 'Fri, 16 Oct 2026 00:00:00 GMT',
        ),
        _response(href: '/b/lexiloop-backup-2026-10-15-000000.json'),
      ]);

      final entries = parseWebdavBackups(xml);

      expect(entries.map((entry) => entry.name).toList(), <String>[
        'lexiloop-backup-2026-10-16-000000.json',
        'lexiloop-backup-2026-10-14-000000.json',
        'lexiloop-backup-2026-10-15-000000.json',
      ]);
    });

    test('条目数封顶，避免目录积累上百份时把界面撑爆', () {
      final responses = <String>[
        for (var index = 0; index < webdavMaxListedBackups + 5; index += 1)
          _response(
            href: '/b/lexiloop-backup-2026-10-16-$index.json',
            size: '1',
          ),
      ];

      expect(
        parseWebdavBackups(_multistatus(responses)),
        hasLength(webdavMaxListedBackups),
      );
    });

    test('非法 XML 按空目录处理，不抛异常', () {
      expect(parseWebdavBackups('<not-closed>'), isEmpty);
      expect(parseWebdavBackups(''), isEmpty);
    });

    test('缺失 getcontentlength 时大小记 0', () {
      final xml = _multistatus(<String>[_response(href: '/b/$_backupName')]);

      expect(parseWebdavBackups(xml).single.sizeBytes, 0);
    });
  });
}
