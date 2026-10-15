/// 选择题选项的**布局**测试。
///
/// **为什么单独写它**：选项此前是一列长短不一、各自居中的胶囊——外层
/// `Column` 没写 `crossAxisAlignment`，而 Flutter 的默认值是 `center`，
/// 于是每个选项按自身文字宽度收缩后被居中。渲染没问题、断言文字也没问题，
/// 所以既有的 widget 测试全绿，只有人眼看得出来。
///
/// 这里从**几何**上钉住：所有选项等宽、占满可用宽度、左边缘对齐。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 构造一道带四个长短悬殊选项的题。
///
/// 手写而不是走服务层：这组用例只关心**几何**，题目怎么来的无关紧要。
StudyItemView buildItem({
  List<String>? choices,
  Map<String, String>? definitions,
}) {
  return StudyItemView(
    itemId: 1,
    position: 0,
    taskType: StudyTaskType.review,
    questionType: QuestionType.enToZhChoice,
    status: StudyItemStatus.pending,
    choices:
        choices ??
        <String>[
          '限制；限制条件（restriction 的复数形式）',
          '运行（trip 的复数）',
          '资格证书；任职资格；职位要求；限定性条件',
          '重要性，重点强调；重读，强调',
        ],
    choiceDefinitions: definitions ?? const <String, String>{},
    word: const StudyWordView(
      id: 1,
      term: 'restrictions',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      contentType: LexicalContentType.word,
      definitions: <DefinitionValue>[],
      pronunciations: <PronunciationView>[],
      examples: <ExampleView>[],
    ),
  );
}

/// 挂载选项组。
Future<void> pumpOptions(
  WidgetTester tester, {
  StudyItemView? item,
  ReviewOutcome? outcome,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: LexiTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ChoiceOptions(
            item: item ?? buildItem(),
            outcome: outcome,
            onAnswer: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 四个选项行（`InkWell` 是选项的可点区域）。
Finder optionTiles() => find.descendant(
  of: find.byType(ChoiceOptions),
  matching: find.byType(InkWell),
);

void main() {
  testWidgets('所有选项等宽，且与最长选项无关', (tester) async {
    // 四个选项的文字长度相差数倍；等宽意味着宽度不再由文字决定。
    await pumpOptions(tester);

    final tiles = optionTiles();
    expect(tiles, findsNWidgets(4));

    final widths = <double>[
      for (var i = 0; i < 4; i += 1) tester.getSize(tiles.at(i)).width,
    ];
    for (final width in widths) {
      expect(width, closeTo(widths.first, 0.5), reason: '选项必须等宽，实际宽度：$widths');
    }
  });

  testWidgets('选项占满可用宽度，且左边缘对齐', (tester) async {
    await pumpOptions(tester);

    final tiles = optionTiles();
    final available = tester.getSize(find.byType(ChoiceOptions)).width;
    final rects = <Rect>[
      for (var i = 0; i < 4; i += 1) tester.getRect(tiles.at(i)),
    ];

    for (final rect in rects) {
      expect(
        rect.width,
        closeTo(available, 0.5),
        reason: '选项应当占满内容宽度（可用 $available，实际 ${rect.width}）',
      );
    }
    for (final rect in rects) {
      expect(
        rect.left,
        closeTo(rects.first.left, 0.5),
        reason: '所有选项的左边缘必须对齐，实际：${rects.map((r) => r.left)}',
      );
    }
  });

  testWidgets('选项内文字左对齐，而不是居中', (tester) async {
    await pumpOptions(tester);

    final first = tester.getRect(find.text('限制；限制条件（restriction 的复数形式）'));
    final tile = tester.getRect(optionTiles().first);
    // 文字块应当贴着选项左侧（留内边距），而不是居中。
    expect(
      first.left - tile.left,
      lessThan(tile.width / 3),
      reason: '选项文字应当左对齐：文字左缘 ${first.left}，选项左缘 ${tile.left}',
    );
  });

  testWidgets('判定为正确 / 错误时带图标，不只靠颜色', (tester) async {
    // 先作答（选中一项），再给出判定——真实流程就是这两步。
    // 直接带 outcome 构造是测不出来的：没有选中项就没有「选错」的那一项。
    await pumpOptions(tester);
    await tester.tap(optionTiles().last);
    await tester.pumpAndSettle();

    await pumpOptions(
      tester,
      outcome: const ReviewOutcome(
        reviewLogId: 1,
        isCorrect: false,
        rating: ReviewRating.again,
        expectedAnswer: '限制；限制条件（restriction 的复数形式）',
        scheduledDays: 1,
        masteryScore: 0,
        masteryLevel: MasteryLevel.newWord,
        wrongWordActive: true,
        idempotent: false,
      ),
    );

    expect(
      find.byIcon(Icons.check_circle_rounded),
      findsOneWidget,
      reason: '正确项要有对勾图标',
    );
    expect(
      find.byIcon(Icons.cancel_rounded),
      findsOneWidget,
      reason: '选错的项要有叉号图标',
    );
  });
}
