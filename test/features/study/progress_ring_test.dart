/// 学习页顶部进度环的几何与语义测试。
///
/// **为什么单独写它**：环是学习页的识别符号，它承载三件事——弧长表达比例、
/// 环内数字是已完成数、旁边一行说还剩多少。这三件事都是「渲染出来才知道」的
/// 几何/语义，普通断言文字存在与否的用例看不出来。
///
/// 另一半是自适应：环 + 文案与计数 + 动作在 360 宽下必须折成两行而不是溢出。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_progress_header.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 造一个进度为 [completed] / [planned] 的会话。
StudySessionView sessionOf({
  required int completed,
  required int planned,
  int correct = 0,
  int wrong = 0,
}) => StudySessionView(
  id: 1,
  mode: StudyMode.daily,
  startedAt: 0,
  plannedCount: planned,
  completedCount: completed,
  correctCount: correct,
  wrongCount: wrong,
  skippedCount: 0,
  items: const <StudyItemView>[],
  resumeIndex: 0,
  resumed: false,
);

/// 渲染头部并返回其尺寸。
Future<Size> pumpHeader(
  WidgetTester tester,
  StudySessionView session, {
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: LexiTheme.light,
      home: Scaffold(
        body: StudyProgressHeader(
          session: session,
          onSkip: () {},
          onExit: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.takeException(), isNull, reason: '头部在 $width 宽下抛异常');
  return tester.getSize(find.byType(StudyProgressHeader));
}

/// 取进度环的绘制器。
CustomPaint ringOf(WidgetTester tester) => tester.widget<CustomPaint>(
  find
      .descendant(
        of: find.byType(StudyProgressHeader),
        matching: find.byType(CustomPaint),
      )
      .first,
);

/// 把进度环画进一张位图，数出强调色像素的数量。
Future<int> accentPixels(
  WidgetTester tester, {
  required int completed,
  required int planned,
}) async {
  await pumpHeader(tester, sessionOf(completed: completed, planned: planned));
  final painter = ringOf(tester).painter!;
  const side = 44;

  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(44, 44));
    final image = await recorder.endRecording().toImage(side, side);
    final data = await image.toByteData();
    image.dispose();
    return data;
  });

  final accent = LexiColors.light.accent;
  var count = 0;
  final rgba = bytes!.buffer.asUint8List();
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] == 0) continue; // 透明像素不算
    final close =
        (rgba[i] - (accent.r * 255).round()).abs() < 24 &&
        (rgba[i + 1] - (accent.g * 255).round()).abs() < 24 &&
        (rgba[i + 2] - (accent.b * 255).round()).abs() < 24;
    if (close) count += 1;
  }
  return count;
}

void main() {
  group('进度环', () {
    testWidgets('直径等于可点区域下限，环内是已完成数', (tester) async {
      await pumpHeader(tester, sessionOf(completed: 12, planned: 45));

      final ring = tester.getSize(
        find
            .descendant(
              of: find.byType(StudyProgressHeader),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(ring.width, 44);
      expect(ring.height, 44);

      // 环内是已完成数（12），不是计划数、也不是百分比。
      expect(
        find.descendant(
          of: find.byType(StudyProgressHeader),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('弧长随比例增长', (tester) async {
      // 绘制器是私有的，读不到 value；直接把环画进一张 44×44 的位图，
      // 数强调色像素——弧长与像素数成正比，这是唯一诚实的验证方式。
      final none = await accentPixels(tester, completed: 0, planned: 4);
      final quarter = await accentPixels(tester, completed: 1, planned: 4);
      final half = await accentPixels(tester, completed: 1, planned: 2);
      final full = await accentPixels(tester, completed: 4, planned: 4);

      expect(none, 0, reason: '进度为 0 时不该画出弧');
      expect(quarter, greaterThan(0));
      expect(half, greaterThan(quarter));
      expect(full, greaterThan(half));
      // 半圈与整圈的像素数应当接近 1:2。
      expect(half / full, closeTo(0.5, 0.12));
    });

    testWidgets('旁边一行说还剩多少，并带上总数', (tester) async {
      await pumpHeader(tester, sessionOf(completed: 12, planned: 45));
      expect(find.text('12 / 45'), findsOneWidget);
      expect(find.text('还剩 33 词'), findsOneWidget);
    });

    testWidgets('全部完成时剩余为 0 而不是负数', (tester) async {
      await pumpHeader(tester, sessionOf(completed: 45, planned: 45));
      expect(find.text('还剩 0 词'), findsOneWidget);
    });

    testWidgets('计划数为 0 时不崩且进度为 0', (tester) async {
      await pumpHeader(tester, sessionOf(completed: 0, planned: 0));
      expect(find.text('还剩 0 词'), findsOneWidget);
    });
  });

  group('自适应', () {
    testWidgets('360 宽下折成两行而不溢出', (tester) async {
      final size = await pumpHeader(
        tester,
        sessionOf(completed: 12, planned: 45),
        width: 360,
      );
      // 两行：环 + 文案一行，计数 + 动作一行。
      expect(size.height, greaterThan(60));
    });

    testWidgets('宽屏下并成一行', (tester) async {
      final size = await pumpHeader(
        tester,
        sessionOf(completed: 12, planned: 45),
      );
      expect(size.height, lessThan(80));
    });

    testWidgets('六档宽度都不溢出', (tester) async {
      for (final width in <double>[320, 360, 420, 700, 1000, 1440]) {
        await pumpHeader(
          tester,
          sessionOf(completed: 12, planned: 45, correct: 9, wrong: 3),
          width: width,
        );
      }
    });
  });
}
