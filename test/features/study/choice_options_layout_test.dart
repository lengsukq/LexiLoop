/// 选择题选项的**布局**测试。
///
/// **为什么单独写它**：选项此前是一列长短不一、各自居中的胶囊——外层
/// `Column` 没写 `crossAxisAlignment`，而 Flutter 的默认值是 `center`，
/// 于是每个选项按自身文字宽度收缩后被居中。渲染没问题、断言文字也没问题，
/// 所以既有的 widget 测试全绿，只有人眼看得出来。
///
/// 这里从**几何**上钉住：所有选项等宽、占满可用宽度、左边缘对齐；
/// 并验证揭示后的标记与「不可改选」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 正确选项的文本（与释义一致）。
const String _correctChoice = '限制；限制条件（restriction 的复数形式）';

/// 构造一道带四个长短悬殊选项的题。
///
/// 手写而不是走服务层：这组用例只关心**几何与揭示态**，题目怎么来的无关紧要。
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
          _correctChoice,
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
      definitions: <DefinitionValue>[
        DefinitionValue(language: 'zh', text: _correctChoice),
      ],
      pronunciations: <PronunciationView>[],
      examples: <ExampleView>[],
    ),
  );
}

/// 挂载选项组；返回选中回调记录。
Future<List<String>> pumpOptions(
  WidgetTester tester, {
  StudyItemView? item,
  String? selected,
  bool revealed = false,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final picked = <String>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: LexiTheme.light,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: ChoiceOptions(
            item: item ?? buildItem(),
            selected: selected,
            revealed: revealed,
            onSelect: picked.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return picked;
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

    final first = tester.getRect(find.text(_correctChoice));
    final tile = tester.getRect(optionTiles().first);
    // 文字块应当贴着选项左侧（留内边距），而不是居中。
    expect(
      first.left - tile.left,
      lessThan(tile.width / 3),
      reason: '选项文字应当左对齐：文字左缘 ${first.left}，选项左缘 ${tile.left}',
    );
  });

  testWidgets('点击选项只上报，不由组件自行揭示', (tester) async {
    final picked = await pumpOptions(tester);
    await tester.tap(optionTiles().last);
    await tester.pumpAndSettle();

    expect(picked, <String>['重要性，重点强调；重读，强调']);
    // 组件仍停留在未揭示态：页面才决定何时揭示。
    expect(find.byIcon(LucideIcons.circleCheck), findsNothing);
  });

  testWidgets('揭示后正确项与选错项带图标，且不可改选', (tester) async {
    final picked = await pumpOptions(
      tester,
      selected: '重要性，重点强调；重读，强调',
      revealed: true,
    );

    expect(
      find.byIcon(LucideIcons.circleCheck),
      findsOneWidget,
      reason: '正确项要有对勾图标',
    );
    expect(
      find.byIcon(LucideIcons.circleX),
      findsOneWidget,
      reason: '选错的项要有叉号图标',
    );

    // 揭示后不再接受点击：先看答案再改选会让会话正确率失真。
    await tester.tap(optionTiles().first);
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
  });
}
