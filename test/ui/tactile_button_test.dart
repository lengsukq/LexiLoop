import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/widgets/tactile_button_face.dart';

Widget example(VoidCallback? onPressed, {bool reduced = false}) => MaterialApp(
  theme: LexiTheme.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: FilledButton(
        autofocus: true,
        onPressed: onPressed,
        child: const Text('开始学习'),
      ),
    ),
  ),
);

void main() {
  testWidgets('按下只呈现反馈，释放仅执行一次操作', (tester) async {
    var calls = 0;
    await tester.pumpWidget(example(() => calls++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pump();
    expect(calls, 0);
    expect(
      tester
          .widget<TactileButtonFace>(find.byType(TactileButtonFace))
          .states
          .contains(WidgetState.pressed),
      isTrue,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减弱动态效果不缩放按钮，保留键盘激活', (tester) async {
    var calls = 0;
    await tester.pumpWidget(example(() => calls++, reduced: true));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(calls, 1);
    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(TactileButtonFace),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.duration, Duration.zero);
    expect(scale.scale, 1);
  });

  testWidgets('禁用操作不激活，仍可正常绘制圆角表面', (tester) async {
    await tester.pumpWidget(example(null));
    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TactileButtonFace>(find.byType(TactileButtonFace))
          .states
          .contains(WidgetState.disabled),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
