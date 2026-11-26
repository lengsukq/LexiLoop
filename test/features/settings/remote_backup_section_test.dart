/// 远程备份设置分组的 widget 测试。
///
/// 钉住四件事：字段改动真的落库、未配置时危险动作不可点、
/// 恢复必须敲关键字、以及状态行会把上次失败读出来。
/// 网络与远端全部由假客户端接管，测试完全离线。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/features/settings/remote_backup_section.dart';
import 'package:lexiloop/services/remote_backup/webdav_providers.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../support/fake_remote_backup_client.dart';

void main() {
  late AppDatabase db;
  late FakeRemoteBackupClient remote;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeRemoteBackupClient();
  });

  tearDown(() async {
    await db.close();
  });

  /// 写入一份完整（或刻意残缺）的 WebDAV 配置。
  Future<void> configure({
    String password = 'app-pass',
    int autoIntervalMinutes = 0,
    String? lastError,
  }) async {
    final settings = SettingsService(SettingsDao(db));
    await settings.update(<String, Object?>{
      webdavSettingsKey: webdavSettingsToStorage(
        WebdavSettings(
          credential: WebdavCredential(
            baseUrl: 'https://dav.example.com/dav',
            directory: '/LexiLoop/',
            username: 'leo',
            password: password,
          ),
          state: WebdavBackupState(
            autoIntervalMinutes: autoIntervalMinutes,
            lastError: lastError,
            lastSuccessAt: lastError == null ? null : 1792069132000,
          ),
        ),
      ),
    }, now: 1);
  }

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          remoteBackupClientFactoryProvider.overrideWithValue(
            (credential) => remote,
          ),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: RemoteBackupSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 读回设置里的 `webdavBackup`。
  Future<WebdavSettings> readSettings() async {
    final service = SettingsService(SettingsDao(db));
    return webdavSettingsFromRaw((await service.load()).raw[webdavSettingsKey]);
  }

  testWidgets('未配置时三个动作都不可点，并提示补全', (tester) async {
    await pumpSection(tester);

    for (final key in <String>[
      'testWebdavConnection',
      'uploadToWebdav',
      'restoreFromWebdav',
    ]) {
      final button = tester.widget<ButtonStyleButton>(find.byKey(Key(key)));
      expect(button.onPressed, isNull, reason: '$key 不该在未配置时可点');
    }
    expect(find.textContaining('填齐地址、账号与密码'), findsOneWidget);
  });

  testWidgets('输入地址与账号后落库，且不影响已有密码', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.enterText(
      find.byKey(const Key('webdavBaseUrlField')),
      'https://nas.example.com/dav',
    );
    await tester.pumpAndSettle();

    final saved = await readSettings();
    expect(saved.credential!.baseUrl, 'https://nas.example.com/dav');
    expect(saved.credential!.password, 'app-pass', reason: '改地址不该抹掉密码');
    expect(saved.credential!.username, 'leo');
  });

  testWidgets('先清空密码再改账号时，地址不会被连带抹掉', (tester) async {
    // 回归用例：合并必须以**原始存储映射**为基准。若拿解析后的凭据当基准，
    // 密码为空时解析结果是 null，改账号就会把地址一起丢掉。
    await configure();
    await pumpSection(tester);

    await tester.enterText(find.byKey(const Key('webdavPasswordField')), '');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('webdavUsernameField')),
      'leo2',
    );
    await tester.pumpAndSettle();

    final loaded = await SettingsService(SettingsDao(db)).load();
    final map = loaded.raw[webdavSettingsKey]! as Map<String, Object?>;
    expect(map['baseUrl'], 'https://dav.example.com/dav');
    expect(map['username'], 'leo2');
    expect(map['password'], '');
  });

  testWidgets('清空地址只清凭据，自动备份周期与状态保留', (tester) async {
    await configure(autoIntervalMinutes: 1440);
    await pumpSection(tester);

    await tester.enterText(find.byKey(const Key('webdavBaseUrlField')), '');
    await tester.pumpAndSettle();

    final saved = await readSettings();
    expect(saved.credential, isNull, reason: '凭据应被清掉');
    expect(
      saved.state.autoIntervalMinutes,
      1440,
      reason: '周期属于状态，不该因为改了地址而一起丢掉',
    );
  });

  testWidgets('清空地址后凭据判定为未配置', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.enterText(find.byKey(const Key('webdavBaseUrlField')), '');
    await tester.pumpAndSettle();

    expect((await readSettings()).credential, isNull);
  });

  testWidgets('密码留空时视为未配置（不允许半份凭据）', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.enterText(find.byKey(const Key('webdavPasswordField')), '');
    await tester.pumpAndSettle();

    final saved = await readSettings();
    expect(saved.credential, isNull, reason: '密码为空 ⇒ 整份凭据无效');
  });

  testWidgets('测试连接调用远端并给出成功提示', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('testWebdavConnection')));
    await tester.pumpAndSettle();

    expect(remote.ensureDirectoryCalls, 1);
    expect(find.text('连接成功，备份目录可用。'), findsOneWidget);
  });

  testWidgets('测试连接失败时显示错误文案', (tester) async {
    await configure();
    remote.failWith = const ExternalServiceError(AppErrorCode.webdavAuthFailed);
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('testWebdavConnection')));
    await tester.pumpAndSettle();

    expect(
      find.text(AppErrorCode.webdavAuthFailed.defaultMessage),
      findsOneWidget,
    );
  });

  testWidgets('点击上传立即执行备份并汇报文件名', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('uploadToWebdav')));
    await tester.pumpAndSettle();

    expect(remote.putCalls, 1);
    expect(remote.backupNames, hasLength(1));
    expect(find.textContaining('已上传'), findsOneWidget);
  });

  testWidgets('恢复空列表给出明确提示', (tester) async {
    await configure();
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('restoreFromWebdav')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webdavEmptyList')), findsOneWidget);
    expect(
      find.text(AppErrorCode.webdavNoBackups.defaultMessage),
      findsOneWidget,
    );
  });

  testWidgets('恢复时列出远端备份并弹出底部确认抽屉', (tester) async {
    await configure();
    const name = 'lexiloop-backup-2026-10-16-101500.json';
    remote.files[name] = Uint8List.fromList(
      utf8.encode('{"format":"lexiloop-json-backup","version":3}'),
    );
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('restoreFromWebdav')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('webdavEntry-$name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('webdavEntry-$name')));
    await tester.pumpAndSettle();

    expect(find.text('用远端备份覆盖本地？'), findsOneWidget);
    expect(
      find.byKey(const Key('restoreFromWebdavConfirmButton')),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('用远端备份覆盖本地？'), findsNothing);
  });

  testWidgets('状态行显示上次失败原因', (tester) async {
    await configure(
      autoIntervalMinutes: 1440,
      lastError: AppErrorCode.webdavUnreachable.code,
    );
    await pumpSection(tester);

    expect(
      find.textContaining(AppErrorCode.webdavUnreachable.defaultMessage),
      findsOneWidget,
    );
  });

  testWidgets('周期选择器显示当前周期，展开后列出全部选项', (tester) async {
    await configure(autoIntervalMinutes: 1440);
    await pumpSection(tester);

    // 收起状态只画当前值。
    expect(find.text(webdavAutoIntervalLabel(1440)), findsOneWidget);

    await tester.tap(find.byKey(const Key('webdavAutoIntervalField')));
    await tester.pumpAndSettle();

    for (final minutes in webdavAutoIntervalOptions) {
      expect(
        find.text(webdavAutoIntervalLabel(minutes)),
        findsWidgets,
        reason: '下拉里应有「${webdavAutoIntervalLabel(minutes)}」',
      );
    }
  });
}
