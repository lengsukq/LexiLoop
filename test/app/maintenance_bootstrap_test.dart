/// 启动点火器的 widget 测试。
///
/// 被测对象只有一个动作：应用启动后后台维护确实被 `start()` 了。
/// 执行器用假实现，因此这里不碰数据库也不联网。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app/maintenance_bootstrap.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';

/// 记录调用序列的假执行器。
class _RecordingRunner implements InitializationJobRunner {
  /// 依次记录的方法名。
  final List<String> calls = <String>[];

  @override
  Future<int> tick({required int now}) async {
    calls.add('tick');
    return 0;
  }

  @override
  Future<int> resetStaleRunningJobs(int now, {bool staleOnly = false}) async {
    calls.add('reset');
    return 0;
  }

  @override
  Future<int> retryFailedJobs(int now) async {
    calls.add('retryFailed');
    return 0;
  }

  @override
  Future<int> decayStaleWrongWords(int now) async {
    calls.add('decay');
    return 0;
  }

  @override
  Future<int> expireStaleImportBatches(int now) async {
    calls.add('expireBatches');
    return 0;
  }
}

void main() {
  late _RecordingRunner runner;

  setUp(() => runner = _RecordingRunner());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          initializationJobRunnerProvider.overrideWithValue(runner),
        ],
        child: const MaterialApp(home: MaintenanceBootstrap(child: _Marker())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('启动后立即走一遍「回收 → 回收失败 → 回收历史数据 → 处理一批」', (tester) async {
    await pumpApp(tester);

    expect(runner.calls, <String>[
      'reset',
      'retryFailed',
      'decay',
      'expireBatches',
      'tick',
    ]);
  });

  testWidgets('子组件被正常渲染', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const Key('marker')), findsOneWidget);
  });
}

/// 被包裹的占位组件。
class _Marker extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox(key: Key('marker')));
}
