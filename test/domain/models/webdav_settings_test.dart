/// WebDAV 设置模型的解析、序列化与归一化测试。
///
/// 这里要钉住三件容易静默出错的事：
/// 1. 目录与地址的归一化——用户会填 `example.com/dav/`、`//a//b`、`dav`；
/// 2. 非法值逐项兜底——单键损坏不该让整份设置消失；
/// 3. 导出时密码被剥掉——这条一旦回归，密码就随备份上传到了那台服务器。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

void main() {
  group('地址与目录归一化', () {
    test('地址去尾斜杠、保留路径', () {
      final credential = WebdavCredential.parse(<String, Object?>{
        'baseUrl': 'https://dav.example.com/dav/',
        'directory': '/LexiLoop',
        'username': 'leo',
        'password': 'app-pass',
      });

      expect(credential, isNotNull);
      expect(credential!.baseUrl, 'https://dav.example.com/dav');
      expect(credential.directory, '/LexiLoop/');
      expect(credential.isConfigured, isTrue);
    });

    test('目录补前后斜杠并把重复斜杠压成一个', () {
      expect(normalizeWebdavDirectory('backups'), '/backups/');
      expect(normalizeWebdavDirectory('//a//b//'), '/a/b/');
      expect(normalizeWebdavDirectory('   '), '/');
    });

    test('缺少协议或主机的地址视为未配置', () {
      for (final bad in <String>[
        '',
        '   ',
        'dav.example.com/dav',
        'ftp://h/x',
      ]) {
        final credential = WebdavCredential.parse(<String, Object?>{
          'baseUrl': bad,
          'username': 'leo',
          'password': 'p',
        });
        expect(credential, isNull, reason: '「$bad」不该被当成可用地址');
      }
    });

    test('账号或密码为空时视为未配置', () {
      for (final missing in <String>['username', 'password']) {
        final raw = <String, Object?>{
          'baseUrl': 'https://dav.example.com',
          'username': 'leo',
          'password': 'p',
        }..remove(missing);
        expect(WebdavCredential.parse(raw), isNull);
      }
    });
  });

  group('目录链与文件 URL', () {
    test('逐级给出从外到内的目录 URL', () {
      final credential = WebdavCredential(
        baseUrl: 'https://h/dav',
        directory: normalizeWebdavDirectory('a/b'),
        username: 'leo',
        password: 'p',
      );

      expect(credential.directoryChain().map((uri) => uri.toString()), <String>[
        'https://h/dav/a/',
        'https://h/dav/a/b/',
      ]);
      expect(credential.directoryUri.toString(), 'https://h/dav/a/b/');
    });

    test('根目录时目录链为空、文件挂在 baseUrl 下', () {
      const credential = WebdavCredential(
        baseUrl: 'https://h',
        directory: '/',
        username: 'leo',
        password: 'p',
      );

      expect(credential.directoryChain(), isEmpty);
      expect(
        credential.fileUri('lexiloop-backup-2026-10-16-101500.json').toString(),
        'https://h/lexiloop-backup-2026-10-16-101500.json',
      );
    });

    test('文件名里的特殊字符按路径段编码', () {
      const credential = WebdavCredential(
        baseUrl: 'https://h',
        directory: '/b',
        username: 'leo',
        password: 'p',
      );

      expect(
        credential.fileUri('a b.json').toString(),
        'https://h/b/a%20b.json',
      );
    });
  });

  group('状态解析', () {
    test('非法周期回落到默认值，超上限被夹住', () {
      expect(
        WebdavBackupState.parse(<String, Object?>{
          'autoIntervalMinutes': 'daily',
        }).autoIntervalMinutes,
        defaultWebdavAutoIntervalMinutes,
      );
      expect(
        WebdavBackupState.parse(<String, Object?>{
          'autoIntervalMinutes': 999999,
        }).autoIntervalMinutes,
        webdavAutoIntervalOptions.last,
      );
      expect(
        WebdavBackupState.parse(<String, Object?>{'autoIntervalMinutes': 0})
            .autoEnabled,
        isFalse,
      );
    });

    test('单个键损坏不影响其他键', () {
      final settings = webdavSettingsFromRaw(<String, Object?>{
        'baseUrl': 'https://h',
        'username': 'leo',
        'password': 'p',
        'autoIntervalMinutes': 0,
        'lastSuccessAt': -5,
        'lastError': 'WEBDAV_AUTH_FAILED',
        'lastCheckpoint': '123:9',
      });

      expect(settings.isConfigured, isTrue);
      expect(settings.state.autoEnabled, isFalse);
      expect(settings.state.lastSuccessAt, isNull, reason: '负数不是时间戳');
      expect(settings.state.lastError, 'WEBDAV_AUTH_FAILED');
      expect(settings.state.lastCheckpoint, '123:9');
    });

    test('copyWith 能显式清掉失败原因', () {
      const state = WebdavBackupState(
        autoIntervalMinutes: 60,
        lastError: 'WEBDAV_REQUEST_FAILED',
      );

      expect(state.copyWith(clearError: true).lastError, isNull);
      expect(state.copyWith(autoIntervalMinutes: 0).lastError, isNotNull);
      expect(state.copyWith().autoIntervalMinutes, 60);
    });
  });

  group('往返与导出', () {
    const settings = WebdavSettings(
      credential: WebdavCredential(
        baseUrl: 'https://h/dav',
        directory: '/LexiLoop/',
        username: 'leo',
        password: 'app-pass',
      ),
      state: WebdavBackupState(
        autoIntervalMinutes: 360,
        lastSuccessAt: 1792069132000,
        lastCheckpoint: '1792069100000:1417',
      ),
    );

    test('写回后能原样解析回来', () {
      final reloaded = webdavSettingsFromRaw(webdavSettingsToStorage(settings));

      expect(reloaded.isConfigured, isTrue);
      expect(reloaded.credential!.baseUrl, 'https://h/dav');
      expect(reloaded.credential!.username, 'leo');
      expect(reloaded.credential!.password, 'app-pass');
      expect(reloaded.state.autoIntervalMinutes, 360);
      expect(reloaded.state.lastSuccessAt, 1792069132000);
      expect(reloaded.state.lastCheckpoint, '1792069100000:1417');
    });

    test('导出时剥掉密码，其余字段保留', () {
      final exported = webdavValueForExport(webdavSettingsToStorage(settings));

      expect(exported, isA<Map<String, Object?>>());
      final map = exported! as Map<String, Object?>;
      expect(map.containsKey('password'), isFalse);
      expect(map['baseUrl'], 'https://h/dav');
      expect(map['username'], 'leo');
      expect(map['autoIntervalMinutes'], 360);
      expect(map['lastSuccessAt'], 1792069132000);
    });

    test('导出时未配置的值原样返回', () {
      expect(webdavValueForExport(null), isNull);
      expect(webdavValueForExport('x'), 'x');
    });

    test('未配置时给出默认周期', () {
      final settings = webdavSettingsFromRaw(null);

      expect(settings.isConfigured, isFalse);
      expect(
        settings.state.autoIntervalMinutes,
        defaultWebdavAutoIntervalMinutes,
      );
    });
  });
}
