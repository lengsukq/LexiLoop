/// 听音辨词 / 词义冲刺视图与结算错词列表的 widget 测试。
///
/// 钉住三件事：
/// - 两个模式复用同一个选项网格，但题面与选项文本不同（词义冲刺的选项
///   只有释义，不能出现词形）；
/// - 进题后自动朗读一次、喇叭按钮可重复点、点选项也会朗读（旧版
///   `games/page.tsx` 的三条朗读规则）；
/// - 结算页的错词行可点开看释义，并给出「看词条详情」入口。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/domain/games/choice_pick.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mistake.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/features/games/game_speech.dart';
import 'package:lexiloop/features/games/widgets/choice_pick_view.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 造一道选择题；词义冲刺的选项是释义，听音辨词的选项是词形。
GameQuestion buildQuestion({
  required GameMode mode,
  int itemId = 1,
  String term = 'cat',
  String definition = '猫',
}) {
  final meaning = mode == GameMode.meaningBlitz;
  return GameQuestion(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(term: term, definition: definition),
    choices: GameChoices(
      options: meaning
          ? <String>[definition, '狗', '猪', '牛']
          : <String>[term, 'dog', 'pig', 'cow'],
      definitions: meaning
          ? const <String, String>{}
          : <String, String>{term: definition},
      correct: meaning ? definition : null,
    ),
    priority: GamePriority.normal,
  );
}

/// 建一局已开始的选择题状态。
ChoicePickState startState(GameMode mode, List<GameQuestion> questions) {
  return choicePickNext(
    startChoicePick(
      plan: gamePlanFor(mode, itemCount: questions.length),
      questions: questions,
    ),
    const StartChoicePick(),
  );
}

void main() {
  /// 记录被朗读的词条，并返回一个固定结果（`WordSpeaker` 也从不抛异常）。
  var spoken = <String>[];

  setUp(() => spoken = <String>[]);

  Future<void> pumpView(
    WidgetTester tester, {
    required ChoicePickState state,
    required ValueChanged<Object> onAction,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          gameSpeakerProvider.overrideWithValue((term) async {
            spoken.add(term);
            return const SystemVoicePlayed();
          }),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChoicePickView(state: state, onAction: onAction),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('词义冲刺题面', () {
    testWidgets('提示、大字词条与只含释义的选项', (tester) async {
      final state = startState(GameMode.meaningBlitz, <GameQuestion>[
        buildQuestion(mode: GameMode.meaningBlitz),
      ]);
      await pumpView(tester, state: state, onAction: (_) {});
      expect(find.text('选择最准确的中文释义'), findsOneWidget);
      expect(find.text('cat'), findsOneWidget, reason: '词条只作为题干出现');
      for (final definition in <String>['猫', '狗', '猪', '牛']) {
        expect(find.text(definition), findsOneWidget);
      }
      expect(find.text('听发音，选择正确的英文词条'), findsNothing);
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
    });
  });

  group('听音辨词题面', () {
    testWidgets('提示、喇叭按钮与带释义副标题的词形选项', (tester) async {
      final state = startState(GameMode.listeningPick, <GameQuestion>[
        buildQuestion(mode: GameMode.listeningPick),
      ]);
      await pumpView(tester, state: state, onAction: (_) {});
      expect(find.text('听发音，选择正确的英文词条'), findsOneWidget);
      expect(find.text('点击可重复播放'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      for (final term in <String>['cat', 'dog', 'pig', 'cow']) {
        expect(find.text(term), findsOneWidget);
      }
      expect(find.text('猫'), findsOneWidget, reason: '释义作为选项副标题');
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
    });

    testWidgets('进题后自动朗读一次，喇叭按钮可重复点', (tester) async {
      final state = startState(GameMode.listeningPick, <GameQuestion>[
        buildQuestion(mode: GameMode.listeningPick),
      ]);
      await pumpView(tester, state: state, onAction: (_) {});
      expect(spoken, isEmpty, reason: '延迟到 $gameAutoSpeakDelayMs 毫秒后才播');
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
      expect(spoken, <String>['cat']);

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();
      expect(spoken, <String>['cat', 'cat'], reason: '喇叭按钮可重复播放');
    });

    testWidgets('点选项会派发动作并朗读该词条', (tester) async {
      final state = startState(GameMode.listeningPick, <GameQuestion>[
        buildQuestion(mode: GameMode.listeningPick),
      ]);
      final actions = <Object>[];
      await pumpView(tester, state: state, onAction: actions.add);
      await tester.tap(find.text('dog'));
      await tester.pump();
      expect(actions.length, 1);
      expect(actions.single, isA<PickChoice>());
      expect((actions.single as PickChoice).choice, 'dog');
      expect(spoken, contains('cat'));
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
    });

    testWidgets('换到下一题会再自动朗读一次', (tester) async {
      final questions = <GameQuestion>[
        buildQuestion(mode: GameMode.listeningPick),
        buildQuestion(
          mode: GameMode.listeningPick,
          itemId: 2,
          term: 'dog',
          definition: '狗',
        ),
      ];
      var state = startState(GameMode.listeningPick, questions);
      final actions = <Object>[];
      await pumpView(tester, state: state, onAction: actions.add);
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
      expect(spoken, <String>['cat']);

      // 点对 → 推进到第 2 题（状态由外部状态机给出，这里直接重算）。
      state = choicePickNext(state, const PickChoice('cat'));
      state = choicePickNext(state, const AdvanceChoicePick());
      await pumpView(tester, state: state, onAction: actions.add);
      await tester.pump(const Duration(milliseconds: gameAutoSpeakDelayMs));
      expect(spoken, <String>['cat', 'dog']);
    });
  });

  group('结算错词列表', () {
    GameResult buildResult() {
      return const GameResult(
        mode: GameMode.meaningBlitz,
        score: 300,
        summary: GameRoundSummary(
          answerScore: 300,
          firstTryCorrect: 1,
          recovered: 1,
          missed: 0,
          mistakeCount: 1,
          maxCombo: 1,
          elapsedMs: 20000,
          durationMs: 45000,
        ),
        rank: GameRank.b,
        leaderboard: GameLeaderboard(
          rank: 1,
          best: 300,
          top: <GameHighScore>[],
          isNewBest: true,
        ),
      );
    }

    Future<void> pumpPanel(
      WidgetTester tester, {
      required ValueChanged<int>? onOpenWord,
    }) async {
      tester.view.physicalSize = const Size(520, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: LexiTheme.light,
          home: Scaffold(
            body: GameResultPanel(
              labels: const GameResultLabels(
                title: '词义冲刺得分',
                primary: '一次正确',
                missed: '未完成',
                exit: '选择其他游戏',
              ),
              result: buildResult(),
              mistakes: const <GameMistake>[
                GameMistake(wordId: 7, term: 'cat', definition: '猫，一种小型家养动物'),
              ],
              onOpenWord: onOpenWord,
              onReplay: () {},
              onExit: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('错词行先给出词条与释义，点开后出现词条详情入口', (tester) async {
      final opened = <int>[];
      await pumpPanel(tester, onOpenWord: opened.add);
      expect(find.text('cat'), findsOneWidget);
      expect(find.text('猫，一种小型家养动物'), findsOneWidget);
      expect(find.text('看词条详情'), findsNothing, reason: '折叠时不给入口');

      await tester.tap(find.text('cat'));
      await tester.pump();
      expect(find.text('看词条详情'), findsOneWidget);

      await tester.tap(find.text('看词条详情'));
      await tester.pump();
      expect(opened, <int>[7]);
    });

    testWidgets('没有跳转回调时只展开释义，不给入口', (tester) async {
      await pumpPanel(tester, onOpenWord: null);
      expect(find.text('猫，一种小型家养动物'), findsOneWidget);
      await tester.tap(find.text('cat'));
      await tester.pump();
      expect(find.text('看词条详情'), findsNothing);
    });
  });
}
