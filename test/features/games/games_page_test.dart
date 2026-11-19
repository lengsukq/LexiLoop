/// 小游戏页面的 widget 测试与控制器单测。
///
/// 覆盖两件事：准备态能渲染出「开始」按钮（规格里点名的验收点），
/// 以及控制器在没有数据库的情况下也能构建——准备态不应该触碰
/// `gameServiceProvider`，否则一进页面就会打开数据库连接。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/features/games/games_page.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/games_setup_view.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  Future<void> pumpGamesPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: LexiTheme.light, home: const GamesPage()),
      ),
    );
    await tester.pump();
  }

  group('控制器', () {
    test('初始为准备态，默认选中单词拼图', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(gamesControllerProvider);
      expect(state, isA<GamesSetup>());
      expect((state as GamesSetup).selectedMode, GameMode.wordBuilder);
      expect(state.loadingMode, isNull);
      expect(state.error, isNull);
    });

    test('selectMode 更新选中项但不开始游戏', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(gamesControllerProvider.notifier)
          .selectMode(GameMode.wordBuilder);
      final state = container.read(gamesControllerProvider) as GamesSetup;
      expect(state.selectedMode, GameMode.wordBuilder);
      expect(state.loadingMode, isNull);
    });
  });

  group('准备页', () {
    testWidgets('渲染精选游戏与「开始」按钮', (tester) async {
      // 6 张卡片在默认的 800×600 测试窗口里放不下，列表会把靠后的卡片
      // 留在视口外不挂载；测试需要一块够高的画布才能断言全部卡片。
      tester.view.physicalSize = const Size(520, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpGamesPage(tester);
      expect(find.text('趣味训练'), findsOneWidget);
      for (final mode in miniGameModes) {
        expect(find.text(gameModeTitle(mode)), findsOneWidget);
        expect(find.text(gameModeSubtitle(mode)), findsOneWidget);
      }
      expect(find.text('开始'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('点击模式卡片后仍只有一个选中标记', (tester) async {
      await pumpGamesPage(tester);
      await tester.tap(find.text('单词拼图'));
      await tester.pump();
      expect(find.byIcon(LucideIcons.circleCheck), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没有溢出异常', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpGamesPage(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
