/// 局域网同步分组的 widget 测试。
///
/// 用真实内存库 + 假的服务端启动器与发现器：这里要钉住的是「界面在四种状态下
/// 分别显示什么」以及「确认门真的挡住了覆盖」——协议与编排各自有专门的用例。
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/features/settings/lan_sync_section.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

import '../../support/fake_lan_sync_client.dart';

void main() {
  late AppDatabase db;
  late FakeLanSyncHostStarter starter;
  late FakeLanSyncClient client;
  late FakeLanSyncClientFactory factory;
  late FakeLanSyncDiscovery discovery;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    starter = FakeLanSyncHostStarter();
    client = FakeLanSyncClient();
    factory = FakeLanSyncClientFactory(client);
    discovery = FakeLanSyncDiscovery();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          lanSyncHostStarterProvider.overrideWithValue(starter.call),
          lanSyncClientFactoryProvider.overrideWithValue(factory.call),
          lanSyncDiscoveryProvider.overrideWithValue(discovery),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: LanSyncSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> startSharing(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('lanSyncStartShare')));
    await tester.pumpAndSettle();
  }

  group('初始状态', () {
    testWidgets('显示设备名、端口与开启共享按钮', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('lanSyncDeviceNameField')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncPortField')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncStartShare')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncPairingCode')), findsNothing);
      expect(find.byKey(const Key('lanSyncDiscover')), findsOneWidget);
    });

    testWidgets('端口输入框预填默认端口，设备名预填平台兜底名', (tester) async {
      await pumpSection(tester);

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lanSyncPortField')))
            .controller
            ?.text,
        '$lanSyncDefaultPort',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lanSyncDeviceNameField')))
            .controller
            ?.text,
        startsWith(lexiloopDeviceNameDefault),
      );
    });
  });

  group('开启共享', () {
    testWidgets('显示配对码、地址与服务次数，并禁用两个输入框', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);

      expect(find.byKey(const Key('lanSyncStartShare')), findsNothing);
      expect(find.byKey(const Key('lanSyncPairingCode')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncShareAddress')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncCopyCode')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncStopShare')), findsOneWidget);
      expect(find.text('已服务 0 次'), findsOneWidget);

      // 共享进行中改端口不会生效，必须禁用。
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lanSyncPortField')))
            .enabled,
        isFalse,
      );
    });

    testWidgets('配对码与设置页里填的设备名一致地传给服务端', (tester) async {
      await pumpSection(tester);
      await tester.enterText(
        find.byKey(const Key('lanSyncDeviceNameField')),
        '书房 Mac',
      );
      await tester.pumpAndSettle();
      await startSharing(tester);

      expect(starter.calls.single.deviceName, '书房 Mac');
      expect(starter.calls.single.pairingCode, hasLength(6));
    });

    testWidgets('服务端报数后界面上的服务次数会更新', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);

      starter.host.serveOnce();
      await tester.pumpAndSettle();

      expect(find.text('已服务 1 次'), findsOneWidget);
    });

    testWidgets('错码踢下线后显示「共享已自动停止」并能重新开启', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);

      starter.host.lockOut();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncLockedOut')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncPairingCode')), findsNothing);
      expect(find.byKey(const Key('lanSyncStartShare')), findsOneWidget);
    });

    testWidgets('启动失败时显示原因而不是空白', (tester) async {
      starter.failure = const ValidationError(
        AppErrorCode.lanSyncHostStartFailed,
      );
      await pumpSection(tester);
      await startSharing(tester);

      expect(find.byKey(const Key('lanSyncShareError')), findsOneWidget);
      expect(
        find.text(AppErrorCode.lanSyncHostStartFailed.defaultMessage),
        findsOneWidget,
      );
    });

    testWidgets('停止共享后回到初始状态', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);

      await tester.tap(find.byKey(const Key('lanSyncStopShare')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncStartShare')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncPairingCode')), findsNothing);
      expect(starter.host.stopCalls, 1);
    });
  });

  group('搜索设备', () {
    testWidgets('没有结果时给出明确的空态文案', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncEmptyHosts')), findsOneWidget);
      expect(discovery.lastTimeout?.inMilliseconds, lanSyncDiscoveryTimeoutMs);
    });

    testWidgets('列出设备名与地址', (tester) async {
      discovery.result = LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          fakeDiscoveredHost(deviceName: '书房 Mac', address: '192.168.1.9'),
        ],
        incompatibleHostCount: 0,
      );
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncHost-192.168.1.9')), findsOneWidget);
      expect(find.text('书房 Mac'), findsOneWidget);
      expect(find.text('192.168.1.9:8765'), findsOneWidget);
    });

    testWidgets('只搜到版本不兼容的设备时说明是版本问题', (tester) async {
      discovery.result = const LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[],
        incompatibleHostCount: 2,
      );
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncDiscoveryNote')), findsOneWidget);
      expect(
        find.text(AppErrorCode.lanSyncProtocolMismatch.defaultMessage),
        findsOneWidget,
      );
    });

    testWidgets('发现器报错时显示原因', (tester) async {
      discovery.failure = const ValidationError(
        AppErrorCode.lanSyncUnsupported,
      );
      await pumpSection(tester);

      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();

      expect(
        find.text(AppErrorCode.lanSyncUnsupported.defaultMessage),
        findsOneWidget,
      );
    });
  });

  group('拉取', () {
    Future<void> discoverOne(WidgetTester tester) async {
      discovery.result = LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[fakeDiscoveredHost()],
        incompatibleHostCount: 0,
      );
      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lanSyncHost-192.168.1.7')));
      await tester.pumpAndSettle();
    }

    testWidgets('配对码不足 6 位时不能进入下一步', (tester) async {
      await pumpSection(tester);
      await discoverOne(tester);

      expect(find.byKey(const Key('lanSyncCodeField')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('lanSyncCodeConfirm')))
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byKey(const Key('lanSyncCodeField')), '1357');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('lanSyncCodeConfirm')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('合并（默认）不要求敲关键字：说明里明说不删本机数据', (tester) async {
      await pumpSection(tester);
      await discoverOne(tester);

      await tester.enterText(
        find.byKey(const Key('lanSyncCodeField')),
        '135790',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lanSyncCodeConfirm')));
      await tester.pumpAndSettle();

      // 默认是合并：没有 RESTORE 输入框，确认按钮直接可用。
      expect(find.byKey(const Key('lanSyncPullConfirmField')), findsNothing);
      expect(find.byKey(const Key('lanSyncMergeConfirm')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('lanSyncMergeConfirm')))
            .onPressed,
        isNotNull,
      );
      expect(factory.calls, isEmpty, reason: '确认之前不许拉取');
    });

    testWidgets('合并在确认后执行，并把目标设备与配对码交给工厂', (tester) async {
      await pumpSection(tester);
      await discoverOne(tester);

      await tester.enterText(
        find.byKey(const Key('lanSyncCodeField')),
        '135790',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lanSyncCodeConfirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lanSyncMergeConfirm')));
      await tester.pumpAndSettle();

      expect(factory.calls.single.code, '135790');
      expect(factory.calls.single.host.address, '192.168.1.7');
      expect(client.calls, <String>['handshake', 'download']);
    });

    testWidgets('切成覆盖后弹出底部危险确认抽屉，确认后才拉取', (tester) async {
      await pumpSection(tester);
      await tester.tap(find.text('覆盖'));
      await tester.pumpAndSettle();
      await discoverOne(tester);

      await tester.enterText(
        find.byKey(const Key('lanSyncCodeField')),
        '135790',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lanSyncCodeConfirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('lanSyncPullConfirmButton')), findsOneWidget);
      expect(find.byKey(const Key('lanSyncMergeConfirm')), findsNothing);
      expect(factory.calls, isEmpty);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('无法撤销'),
        ),
        findsOneWidget,
        reason: '正文必须说清这一步不可逆',
      );

      await tester.tap(find.byKey(const Key('lanSyncPullConfirmButton')));
      await tester.pumpAndSettle();
      expect(client.calls, <String>['handshake', 'download']);
    });

    testWidgets('配对码错误时弹出提示且不改动数据', (tester) async {
      client.handshakeFailure = const ValidationError(
        AppErrorCode.lanSyncCodeInvalid,
      );
      await pumpSection(tester);
      await discoverOne(tester);

      await tester.enterText(
        find.byKey(const Key('lanSyncCodeField')),
        '000000',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('lanSyncCodeConfirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lanSyncMergeConfirm')));
      await tester.pumpAndSettle();

      expect(
        find.text(AppErrorCode.lanSyncCodeInvalid.defaultMessage),
        findsOneWidget,
      );
      expect(client.calls, <String>['handshake']);
    });
  });

  group('同步方式', () {
    testWidgets('默认是合并，提示文案说明不会删本机数据', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const Key('lanSyncPullMode')), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<LanSyncPullMode>>(
              find.byKey(const Key('lanSyncPullMode')),
            )
            .selected,
        <LanSyncPullMode>{LanSyncPullMode.merge},
      );
      expect(find.textContaining('本机现有数据全部保留'), findsOneWidget);
    });

    testWidgets('切到覆盖会落盘并换成危险色提示', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.text('覆盖'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<LanSyncPullMode>>(
              find.byKey(const Key('lanSyncPullMode')),
            )
            .selected,
        <LanSyncPullMode>{LanSyncPullMode.replace},
      );
      expect(find.textContaining('整体替换本机'), findsOneWidget);

      // 落盘：重建整棵树后仍是覆盖。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpSection(tester);
      expect(
        tester
            .widget<SegmentedButton<LanSyncPullMode>>(
              find.byKey(const Key('lanSyncPullMode')),
            )
            .selected,
        <LanSyncPullMode>{LanSyncPullMode.replace},
      );
    });
  });

  group('拉取时的自我过滤', () {
    testWidgets('把本机共享会话的标识交给发现器', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);
      final instanceId = starter.calls.single.instanceId;

      discovery.result = LanSyncDiscoveryResult(
        hosts: <DiscoveredLanHost>[
          fakeDiscoveredHost(instanceId: instanceId, deviceName: '本机'),
          fakeDiscoveredHost(instanceId: 'other', deviceName: '手机'),
        ],
        incompatibleHostCount: 0,
      );
      await tester.tap(find.byKey(const Key('lanSyncDiscover')));
      await tester.pumpAndSettle();

      expect(find.text('本机'), findsNothing);
      expect(find.text('手机'), findsOneWidget);
    });
  });

  group('导出 hooks', () {
    testWidgets('共享导出的是当前库的备份', (tester) async {
      await pumpSection(tester);
      await startSharing(tester);

      final backup = await starter.calls.single.backupSource();
      expect(backup.fileName, startsWith('lexiloop-backup-'));
      expect(backup.bytes, isA<Uint8List>());
    });
  });
}
