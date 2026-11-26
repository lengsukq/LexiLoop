/// 「双端词环共振桥」动画面板的 widget 测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/features/settings/lan_sync/lan_sync_theater.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  const local = LanSyncEndpoint(
    name: '书房 Mac',
    deviceKind: lanSyncDeviceKindDesktop,
  );
  const peer = LanSyncEndpoint(
    name: '随身手机',
    deviceKind: lanSyncDeviceKindMobile,
  );

  Future<void> pumpTheater(
    WidgetTester tester, {
    required LanSyncTransferProgress progress,
    VoidCallback? onCancel,
    VoidCallback? onDismiss,
    VoidCallback? onRetry,
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: LexiTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: LanSyncTheater(
                progress: progress,
                onCancel: onCancel,
                onDismiss: onDismiss,
                onRetry: onRetry,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('传输中显示增量标签、压缩节省比例与取消按钮', (tester) async {
    var cancelled = false;
    await pumpTheater(
      tester,
      onCancel: () => cancelled = true,
      progress: const LanSyncTransferProgress(
        phase: LanSyncPhase.transferring,
        direction: LanSyncDirection.bidirectional,
        local: local,
        peer: peer,
        detail: LanSyncProgressDetail(
          isIncremental: true,
          bytes: LanSyncByteMetrics(
            sentBytes: 24 * 1024,
            totalSendBytes: 48 * 1024,
            receivedBytes: 18 * 1024,
            totalReceiveBytes: 36 * 1024,
            uncompressedBytes: 512 * 1024,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('双向 · 增量'), findsOneWidget);
    expect(find.byKey(const Key('lanSyncTheaterTelemetry')), findsOneWidget);
    expect(find.textContaining('压缩省'), findsOneWidget);
    expect(find.text('书房 Mac'), findsOneWidget);
    expect(find.text('随身手机'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lanSyncTheaterCancel')));
    expect(cancelled, isTrue);
  });

  testWidgets('完成后展示双侧战果摘要并可正常 pumpAndSettle', (tester) async {
    var dismissed = false;
    await pumpTheater(
      tester,
      onDismiss: () => dismissed = true,
      progress: const LanSyncTransferProgress(
        phase: LanSyncPhase.completed,
        direction: LanSyncDirection.bidirectional,
        local: local,
        peer: peer,
        detail: LanSyncProgressDetail(
          isIncremental: true,
          localSummary: LanSyncDeltaSummary(
            addedWords: 3,
            addedLogs: 12,
            wordCount: 500,
          ),
          peerSummary: LanSyncDeltaSummary(
            addedWords: 1,
            addedLogs: 5,
            wordCount: 500,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('增量同步完成'), findsOneWidget);
    expect(find.text('+3 词 · +12 复习'), findsOneWidget);
    expect(find.text('+1 词 · +5 复习'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lanSyncTheaterDismiss')));
    expect(dismissed, isTrue);
  });

  testWidgets('失败态显示错误文案与重试按钮', (tester) async {
    var retried = false;
    await pumpTheater(
      tester,
      onRetry: () => retried = true,
      progress: LanSyncTransferProgress(
        phase: LanSyncPhase.failed,
        direction: LanSyncDirection.bidirectional,
        local: local,
        peer: peer,
        detail: LanSyncProgressDetail(
          errorCode: AppErrorCode.lanSyncCodeInvalid.code,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppErrorCode.lanSyncCodeInvalid.defaultMessage),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('lanSyncTheaterRetry')));
    expect(retried, isTrue);
  });

  testWidgets('共振桥舞台始终撑满卡片宽度，不会塌缩遮挡双侧设备图标', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpTheater(
      tester,
      progress: const LanSyncTransferProgress(
        phase: LanSyncPhase.transferring,
        direction: LanSyncDirection.bidirectional,
        local: local,
        peer: peer,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final paintSize = tester.getSize(
      find
          .descendant(
            of: find.byKey(const Key('lanSyncTheater')),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    expect(
      paintSize.width,
      greaterThan(500),
      reason: '词环共振桥画布必须撑满卡片宽度，防止双端节点塌缩重叠',
    );
  });

  testWidgets('减弱动态效果模式下无持续动画并可稳定结算', (tester) async {
    await pumpTheater(
      tester,
      disableAnimations: true,
      progress: const LanSyncTransferProgress(
        phase: LanSyncPhase.transferring,
        direction: LanSyncDirection.bidirectional,
        local: local,
        peer: peer,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('lanSyncTheater')), findsOneWidget);
  });
}
