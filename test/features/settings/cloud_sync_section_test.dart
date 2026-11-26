import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/models/cloud_sync_progress.dart';
import 'package:lexiloop/features/settings/cloud_sync_section.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

class _WidgetFakeCloudClient implements CloudSyncClient {
  int handshakeCalls = 0;
  int pullCalls = 0;
  int pushCalls = 0;

  @override
  Future<CloudSyncHandshakeReply> handshake(
    CloudSyncHandshakeRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    handshakeCalls += 1;
    return const CloudSyncHandshakeReply(
      deviceId: 'srv-01',
      datasetEpoch: 'ep-01',
      serverNow: 1730000000000,
      wordCount: 5,
    );
  }

  @override
  Future<CloudSyncPullPage> pullPage(
    CloudSyncPullRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    pullCalls += 1;
    return const CloudSyncPullPage(
      meta: CloudSyncPullMeta(
        serverNow: 1730000000000,
        snapshotAt: 1730000000000,
        datasetEpoch: 'ep-01',
        hasMore: false,
      ),
      tables: <String, List<Map<String, Object?>>>{},
      wordRefs: <Map<String, Object?>>[],
      wireBytes: 64,
      isIncremental: true,
    );
  }

  @override
  Future<CloudSyncPushReply> pushBatch(
    CloudSyncPushRequest request, {
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    pushCalls += 1;
    return const CloudSyncPushReply(
      summary: CloudSyncSideCounts(wordCount: 5),
      datasetEpoch: 'ep-01',
      serverNow: 1730000000000,
      wireBytes: 32,
    );
  }
}

void main() {
  late AppDatabase db;
  late _WidgetFakeCloudClient fakeClient;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fakeClient = _WidgetFakeCloudClient();
  });

  tearDown(() => db.close());

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          cloudSyncClientFactoryProvider.overrideWithValue((_) => fakeClient),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: CloudSyncSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'disables actions until valid URL is entered, then tests & syncs',
    (tester) async {
      await pumpSection(tester);

      final startBtnBefore = tester.widget<FilledButton>(
        find.byKey(const Key('cloudSyncStartButton')),
      );
      expect(startBtnBefore.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('cloudSyncBaseUrlField')),
        'https://lexiloop.vercel.app',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cloudSyncTestButton')));
      await tester.pumpAndSettle();
      expect(fakeClient.handshakeCalls, 1);
      expect(find.textContaining('云端当前共 5 个词条'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cloudSyncStartButton')));
      await tester.pumpAndSettle();
      expect(fakeClient.pullCalls, 1);
      expect(fakeClient.pushCalls, 1);
    },
  );

  testWidgets('pullReplace requires confirmation sheet before running', (
    tester,
  ) async {
    await pumpSection(tester);
    await tester.enterText(
      find.byKey(const Key('cloudSyncBaseUrlField')),
      'https://lexiloop.vercel.app',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('覆盖'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cloudSyncStartButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(cloudSyncReplaceConfirmButtonKey), findsOneWidget);
    expect(fakeClient.pullCalls, 0);

    await tester.tap(find.byKey(cloudSyncReplaceConfirmButtonKey));
    await tester.pumpAndSettle();
    expect(fakeClient.pullCalls, 1);
  });
}
