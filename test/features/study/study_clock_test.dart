/// 学习活跃计时器的单测。
///
/// 对应旧版 `src/lib/use-active-stopwatch.ts`。这里钉的是「暂停」本身：
/// 空闲、失焦、结算都必须**真的停表**，而不是事后把总时长夹一刀——
/// 后者会把「挂机 3 分钟再敲一个字」整段算成活跃。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/features/study/study_clock.dart';

/// 与 `tester.pump` 同步的假时钟。
///
/// `StudyClock` 的 `Timer` 在 widget 测试里走假时间，而 `DateTime.now()` 走
/// 真实时间；不注入 `binding.clock` 就永远构造不出「空闲 45 秒」。
StudyClock _clock(WidgetTester tester) =>
    StudyClock(now: () => tester.binding.clock.now().millisecondsSinceEpoch);

void main() {
  testWidgets('只有答题状态下才累计', (tester) async {
    final clock = _clock(tester);

    await tester.pump(const Duration(seconds: 10));
    expect(clock.elapsedMs(), 0, reason: '尚未开始答题');

    clock.setEnabled(enabled: true);
    await tester.pump(const Duration(seconds: 10));
    expect(clock.elapsedMs(), 10 * secondMs);

    clock.dispose();
  });

  testWidgets('揭示答案（停用）后不再累计', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 6));
    clock.setEnabled(enabled: false);
    await tester.pump(const Duration(seconds: 60));

    expect(clock.elapsedMs(), 6 * secondMs);
    clock.dispose();
  });

  testWidgets('45 秒无交互后不再累计', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 10));
    expect(clock.elapsedMs(), 10 * secondMs);

    await tester.pump(const Duration(minutes: 5));
    expect(
      clock.elapsedMs(),
      activeIdleTimeoutMs,
      reason: '空闲定时器应在最后一次交互后的 45 秒关掉活跃段',
    );

    clock.dispose();
  });

  testWidgets('失焦暂停，回到前台后继续', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 8));
    clock.setVisible(visible: false);
    await tester.pump(const Duration(seconds: 120));
    expect(clock.elapsedMs(), 8 * secondMs, reason: '失焦期间一秒都不该计入');

    clock.setVisible(visible: true);
    await tester.pump(const Duration(seconds: 4));
    expect(clock.elapsedMs(), 12 * secondMs);

    clock.dispose();
  });

  testWidgets('失焦期间即使收到交互也不恢复计时', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 5));
    clock
      ..setVisible(visible: false)
      ..touch();
    await tester.pump(const Duration(seconds: 30));

    expect(clock.elapsedMs(), 5 * secondMs);
    clock.dispose();
  });
  testWidgets('reset 清零并重新开始计时', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 20));
    expect(clock.elapsedMs(), 20 * secondMs);

    clock.reset();
    expect(clock.elapsedMs(), 0);

    await tester.pump(const Duration(seconds: 3));
    expect(clock.elapsedMs(), 3 * secondMs);

    clock.dispose();
  });

  testWidgets('capture 返回累计值并停止计时', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 7));
    expect(clock.capture(), 7 * secondMs);

    await tester.pump(const Duration(minutes: 3));
    expect(clock.elapsedMs(), 7 * secondMs, reason: '结算之后不该再累计');
  });

  testWidgets('暂停后恢复只累加真实活跃段', (tester) async {
    final clock = _clock(tester)..setEnabled(enabled: true);

    await tester.pump(const Duration(seconds: 10));
    clock.touch();
    // 之后 200 秒没有任何交互：只有前 45 秒算活跃。
    await tester.pump(const Duration(seconds: 200));
    expect(clock.elapsedMs(), 10 * secondMs + activeIdleTimeoutMs);

    clock.touch();
    await tester.pump(const Duration(seconds: 5));
    expect(
      clock.elapsedMs(),
      10 * secondMs + activeIdleTimeoutMs + 5 * secondMs,
    );

    clock.dispose();
  });

  testWidgets('累计时长永远不超过墙钟时间', (tester) async {
    final startMs = tester.binding.clock.now().millisecondsSinceEpoch;
    final clock = _clock(tester)..setEnabled(enabled: true);

    Future<void> expectWithinWallClock() async {
      final wallMs =
          tester.binding.clock.now().millisecondsSinceEpoch - startMs;
      expect(clock.elapsedMs(), lessThanOrEqualTo(wallMs));
    }

    await tester.pump(const Duration(seconds: 20));
    await expectWithinWallClock();
    clock.touch();
    await tester.pump(const Duration(minutes: 10));
    await expectWithinWallClock();
    clock.setVisible(visible: false);
    await tester.pump(const Duration(minutes: 10));
    await expectWithinWallClock();
    clock.setVisible(visible: true);
    await tester.pump(const Duration(seconds: 30));
    await expectWithinWallClock();

    clock.dispose();
  });
}
